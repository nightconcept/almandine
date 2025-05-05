--[[
  add
  @module add

  Provides functionality to add a dependency to the project manifest and download it to a designated directory.
]]

local filesystem_utils = require("utils.filesystem")
local url_utils = require("utils.url")

---@class AddDeps
---@field load_manifest fun(): table, string?
---@field save_manifest fun(manifest: table): boolean, string?
---@field ensure_lib_dir fun(): nil
---@field downloader table
---@field downloader.download fun(url: string, path: string, verbose: boolean|nil): boolean, string?
---@field hash_utils table
-- luacheck: ignore
---@field hash_utils.hash_file_sha256 fun(path: string): string?, string?, boolean?, string? -- hash, fatal_err, warning_occurred, warning_msg
---@field lockfile table
---@field lockfile.generate_lockfile_table fun(deps: table): table
---@field lockfile.write_lockfile fun(table): boolean, string?
---@field lockfile.load_lockfile fun(): table?, string?
---@field verbose boolean|nil Whether to run downloader in verbose mode.
---@field printer table Printer utility with stdout/stderr methods.

---@param dep_name string|nil Dependency name to add. If nil, inferred from source URL.
---@param dep_source string|table Dependency source string (URL) or table with url/path.
---@param dest_dir string|nil Optional destination directory or full path provided via command line (-d).
---@param deps AddDeps Table containing dependency injected functions and configuration.
---@return boolean success True if core operation completed successfully (download, manifest update).
---@return string? error Error message if a fatal operation failed.
---@return boolean warning True if a non-fatal warning occurred (e.g. hash failure).
---@return string? warning_message The warning message if a warning occurred.
---@return boolean success True if successful, false otherwise.
---@return string|nil output_message Message for stdout.
---@return string|nil error_message Message for stderr.
local function add_dependency(dep_name, dep_source, dest_dir, deps)
  local verbose = deps.verbose or false
  local output_messages = {}
  local error_messages = {}

  -- TODO: Standardize the number of returns. Have the return state continually update so that it's obvious what we are returning
  -- in each return statement.

  -- TODO: Cleanup the return statements so that most of them show only if verbose. Only the final states should really be shown to the Update staged for next run.
  -- Compare with pnpm to see what it shows in all these cases.

  -- Load Manifest & Ensure Library Directory
  deps.ensure_lib_dir()
  local manifest, manifest_err = deps.load_manifest()
  if not manifest then
    -- No need to print here, main.lua handles printing errors
    return false, nil, "Error loading manifest: " .. (manifest_err or "Unknown error")
  end

  -- Process Input Source (URL/Table)
  local input_url
  local input_path -- Path provided explicitly in dep_source table (rare)

  if type(dep_source) == "table" then
    input_url = dep_source.url
    input_path = dep_source.path -- Path from source table, not -d flag
    if not input_url then
      return false, nil, "Dependency source table must contain a 'url' field."
    end
  else
    input_url = dep_source
    input_path = nil
  end

  -- Determine Dependency Name and Filename
  local filename
  if dep_name then
    -- Use provided name (-n)
    filename = dep_name .. ".lua"
  else
    -- Infer filename from URL
    filename = input_url:match("/([^/]+)$")
    if not filename or filename == "" then
      return false, nil, "Could not determine filename from URL: " .. input_url .. ". Try using the -n flag."
    end
    -- Infer dep_name from filename if not provided
    local name_from_file = filename:match("^(.+)%.lua$")
    if name_from_file then
      dep_name = name_from_file
    else
      -- This case might be hard to reach if filename extraction worked, but safeguarding.
      return false, nil, "Could not infer dependency name from URL/filename: " .. input_url
    end
  end
  -- At this point, both dep_name and filename should be set.

  -- Normalize URL & Get Download Info
  -- Returns: download_url, error
  local _, _, commit_hash, download_url, norm_err = url_utils.normalize_github_url(input_url)
  if norm_err then
    return false, nil, string.format("Failed to process URL '%s': %s", input_url, norm_err)
  end
  if not download_url then
    -- TODO: Should be caught by normalize_github_url errors usually, but double-check
    return false, nil, string.format("Could not determine download URL for '%s'", input_url)
  end

  -- Create Source Identifier for Manifest
  local source_identifier, sid_err = url_utils.create_github_source_identifier(input_url)
  if not source_identifier then
    -- Treat this as a non-fatal warning for now, allows proceeding with original URL
    local warn_msg = string.format(
      "Could not create specific GitHub identifier for '%s' (%s). Using original URL.",
      input_url,
      sid_err or "unknown error"
    )
    table.insert(error_messages, "Warning: " .. warn_msg)
    source_identifier = input_url -- Fallback to the original URL
  end

  -- Determine Final Target Path
  local target_path
  if dest_dir then
    -- User provided -d flag
    local ends_with_sep = dest_dir:match("[/]$")
    local path_type = filesystem_utils.get_path_type(dest_dir)

    if path_type == "directory" or ends_with_sep then
      local dir_to_join = dest_dir:gsub("[/\\]$", "") -- Remove trailing / or \
      target_path = filesystem_utils.join_path(dir_to_join, filename)
    else
      target_path = dest_dir -- Treat as full path
    end
  elseif input_path then
    -- Path provided via table source (rare)
    target_path = input_path
  else
    -- Default path
    target_path = filesystem_utils.join_path("src", "lib", filename)
  end

  -- Ensure Target Directory Exists
  local target_dir_path = target_path:match("(.+)[\\/]")
  if target_dir_path then
    local dir_ok, dir_err = filesystem_utils.ensure_dir_exists(target_dir_path)
    if not dir_ok then
      local err_msg =
        string.format("Failed to ensure target directory '%s' exists: %s", target_dir_path, dir_err or "unknown error")
      return false, nil, err_msg
    end
  end

  -- Prepare Manifest Update (but don't save yet)
  manifest.dependencies = manifest.dependencies or {}
  manifest.dependencies[dep_name] = {
    source = source_identifier,
    path = target_path,
  }
  table.insert(output_messages,
    string.format("Preparing to add dependency '%s': source='%s', path='%s'", dep_name, source_identifier, target_path)
  )

  -- Download Dependency
  table.insert(output_messages, string.format("Downloading '%s' from '%s' to '%s'...", dep_name, download_url, target_path))
  local download_ok, download_err = deps.downloader.download(download_url, target_path, verbose)

  if not download_ok then
    table.insert(error_messages, string.format("Error: Failed to download '%s'.", dep_name))
    table.insert(error_messages, "  URL: " .. download_url)
    table.insert(error_messages, "  Reason: " .. (download_err or "Unknown error"))
    table.insert(error_messages, "  Manifest and lockfile were NOT updated.")
    -- Attempt to remove potentially partially downloaded file
    local removed, remove_err = filesystem_utils.remove_file(target_path)
    if not removed then
      table.insert(error_messages, string.format(
        "Warning: Could not remove partially downloaded file '%s': %s",
        target_path,
        remove_err or "unknown error"
      ))
    end
    -- Return combined output/error messages
    return false, table.concat(output_messages, "\n"), table.concat(error_messages, "\n")
  end

  -- Download Succeeded: Save Manifest
  table.insert(output_messages, string.format("Successfully downloaded '%s' to '%s'.", dep_name, target_path))
  local ok_save, err_save = deps.save_manifest(manifest)
  if not ok_save then
    -- Critical error: downloaded file exists, but manifest doesn't reflect it.
    local err_msg = "Critical Error: Failed to save project.lua after successful download: "
      .. (err_save or "Unknown error")
    table.insert(error_messages, err_msg)
    table.insert(error_messages, "  The downloaded file exists at: " .. target_path)
    table.insert(error_messages, "  The manifest (project.lua) may be inconsistent.")
    return false, table.concat(output_messages, "\n"), table.concat(error_messages, "\n")
  end
  table.insert(output_messages, "Updated project.lua.")

  -- Update Lockfile
  local existing_lockfile_data, load_err = deps.lockfile.load_lockfile()
  if load_err and not load_err:match("Could not read lockfile") then
    -- Warn but continue, create a new lockfile or overwrite based on current state.
    local load_warn_msg = "Could not load existing lockfile to merge changes: " .. tostring(load_err)
    table.insert(error_messages, "Warning: " .. load_warn_msg)
    -- Aggregate warnings
    existing_lockfile_data = nil -- Treat as if no lockfile existed
  end

  local current_lock_packages = (existing_lockfile_data and existing_lockfile_data.package) or {}

  if current_lock_packages[dep_name] then
    table.insert(output_messages, string.format("Updating existing entry for '%s' in lockfile.", dep_name))
  else
    table.insert(output_messages, "Adding new entry to lockfile...")
  end

  -- Determine lockfile hash
  local lockfile_hash_string
  if commit_hash then
    lockfile_hash_string = "commit:" .. commit_hash
    table.insert(output_messages, string.format("Using commit hash '%s' for lockfile entry '%s'.", commit_hash, dep_name))
  else
    table.insert(output_messages, string.format("Calculating sha256 content hash for '%s'...", target_path))
    -- Adjusted call to handle 4 return values
    local content_hash, hash_fatal_err, hash_warning_occurred, hash_warning_msg = deps.hash_utils.hash_file_sha256(target_path)

    if content_hash then
      lockfile_hash_string = "sha256:" .. content_hash
      table.insert(output_messages, string.format("Using content hash '%s' for lockfile entry '%s'.", content_hash, dep_name))
    elseif hash_warning_occurred then
      -- Specific non-fatal warning: hash tool not found
      lockfile_hash_string = "hash_error:tool_not_found"
      -- Aggregate warning
      table.insert(error_messages, "Warning: " .. (hash_warning_msg or "Hash tool not found"))
    else
      -- Some other fatal error occurred during hashing (file not found, command failed, parse error)
      -- Treat as non-fatal warning
      lockfile_hash_string = "hash_error:" .. (hash_fatal_err or "unknown_fatal_error")
      local hash_fail_warn_msg = string.format("Failed to calculate sha256 hash for '%s': %s", target_path, hash_fatal_err or "unknown error")
      table.insert(error_messages, "Warning: " .. hash_fail_warn_msg)
    end
  end

  -- Add/Update lockfile entry
  current_lock_packages[dep_name] = {
    -- Use the raw download URL for reproducibility, as it includes the specific ref used.
    source = download_url,
    path = target_path,
    hash = lockfile_hash_string,
  }

  -- Generate and write the lockfile
  local lockfile_table = deps.lockfile.generate_lockfile_table(current_lock_packages)
  local ok_lock, err_lock = deps.lockfile.write_lockfile(lockfile_table)

  if not ok_lock then
    -- Error saving lockfile, but manifest is already saved.
    local err_msg = "Error: Failed to write almd-lock.lua: " .. (err_lock or "Unknown error")
    table.insert(error_messages, err_msg)
    table.insert(error_messages, "  The manifest (project.lua) was updated, but the lockfile update failed.")
    -- Treat lockfile write failure as fatal
    return false, table.concat(output_messages, "\n"), table.concat(error_messages, "\n")
  end

  table.insert(output_messages, "Successfully updated almd-lock.lua.")
  -- Return success, potentially with warnings
  -- Combine messages for return
  local final_output = table.concat(output_messages, "\n")
  local final_error = nil
  if #error_messages > 0 then
    final_error = table.concat(error_messages, "\n")
  end

  -- Success: return true, output, errors (which act as warnings here)
  return true, final_output, final_error
end

---Prints usage/help information for the `add` command.
---@return string Usage string for the add command.
local function help_info()
  return [[
Usage: almd add <source> [-d <path>] [-n <name>] [--verbose]

Adds a dependency to the project manifest (project.lua) and downloads it.
Updates the lockfile (almd-lock.lua) with the resolved download URL and hash.

Arguments:
  <source>     URL of the dependency (e.g., GitHub blob/raw URL) or a Lua table string.

Options:
  -d <path>    Destination path. Can be a directory (file saved as <name>.lua inside)
               or a full file path (e.g., src/vendor/custom_name.lua).
               Defaults to 'src/lib/<name>.lua'.
  -n <name>    Specify the dependency name used in project.lua and the default filename.
               If omitted, name is inferred from the <source> URL's filename part.
  --verbose    Enable verbose output during download.

Examples:
  # Add from GitHub URL, infer name 'mylib'
  almd add https://github.com/user/repo/blob/main/mylib.lua

  # Add with a specific name 'mybetterlib'
  almd add https://github.com/user/repo/blob/main/mylib.lua -n mybetterlib

  # Add to a specific directory 'src/vendor/' (will be saved as src/vendor/mylib.lua)
  almd add https://github.com/user/repo/blob/main/mylib.lua -d src/vendor/

  # Add to a specific file path 'src/ext/differentlib.lua'
  almd add https://github.com/user/repo/blob/main/mylib.lua -d src/ext/differentlib.lua

  # Add from a Gist (name inferred)
  almd add https://gist.githubusercontent.com/user/gistid/raw/commithash/mylib.lua
]]
end

return {
  add_dependency = add_dependency,
  help_info = help_info,
}
