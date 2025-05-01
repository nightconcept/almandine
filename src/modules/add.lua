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
---@field downloader.download fun(url: string, path: string, verbose: boolean|nil): boolean, string? -- Added verbose flag
---@field hash_utils table
---@field hash_utils.hash_file_sha256 fun(path: string): string?, string? -- Adjusted signature based on usage
---@field lockfile table
---@field lockfile.generate_lockfile_table fun(deps: table): table
---@field lockfile.write_lockfile fun(table): boolean, string?
---@field lockfile.load_lockfile fun(): table?, string?
---@field verbose boolean|nil Whether to run downloader in verbose mode.

---@param dep_name string|nil Dependency name to add. If nil, inferred from source URL.
---@param dep_source string|table Dependency source string (URL) or table with url/path.
---@param cmd_dest_path_or_dir string|nil Optional destination directory or full path provided via command line (-d).
---@param deps AddDeps Table containing dependency injected functions and configuration.
---@return boolean success True if operation completed successfully.
---@return string? error Error message if operation failed.
local function add_dependency(dep_name, dep_source, cmd_dest_path_or_dir, deps)
  local verbose = deps.verbose or false

  -- 1. Load Manifest & Ensure Library Directory
  deps.ensure_lib_dir()
  local manifest, manifest_err = deps.load_manifest()
  if not manifest then
    print("Error loading manifest: " .. (manifest_err or "Unknown error"))
    return false, manifest_err
  end

  -- 2. Process Input Source (URL/Table)
  local input_url
  local input_path -- Path provided explicitly in dep_source table (rare)

  if type(dep_source) == "table" then
    input_url = dep_source.url
    input_path = dep_source.path -- Path from source table, not -d flag
    if not input_url then
      return false, "Dependency source table must contain a 'url' field."
    end
  else
    input_url = dep_source
    input_path = nil
  end

  -- 3. Determine Dependency Name and Filename
  local filename
  if dep_name then
    -- Use provided name (-n)
    filename = dep_name .. ".lua"
  else
    -- Infer filename from URL
    filename = input_url:match("/([^/]+)$")
    if not filename or filename == "" then
      return false, "Could not determine filename from URL: " .. input_url .. ". Try using the -n flag."
    end
    -- Infer dep_name from filename if not provided
    local name_from_file = filename:match("^(.+)%.lua$")
    if name_from_file then
      dep_name = name_from_file
    else
      -- This case might be hard to reach if filename extraction worked, but safeguarding.
      return false, "Could not infer dependency name from URL/filename: " .. input_url
    end
  end
  -- At this point, both dep_name and filename should be set.

  -- 4. Normalize URL & Get Download Info
  -- Returns: base_url, ref, commit_hash (only if ref is hash), download_url, error
  local base_url, ref, commit_hash, download_url, norm_err = url_utils.normalize_github_url(input_url)
  if norm_err then
    return false, string.format("Failed to process URL '%s': %s", input_url, norm_err)
  end
  if not download_url then
    -- Should be caught by normalize_github_url errors usually, but double-check
    return false, string.format("Could not determine download URL for '%s'", input_url)
  end

  -- 5. Create Source Identifier for Manifest
  local source_identifier, sid_err = url_utils.create_github_source_identifier(input_url)
  if not source_identifier then
    print(
      string.format(
        "Warning: Could not create specific GitHub identifier for '%s' (%s). Using original URL.",
        input_url,
        sid_err or "unknown error"
      )
    )
    source_identifier = input_url -- Fallback to the original URL
    -- Note: commit_hash might still be known from normalization step even if identifier creation failed.
  end

  -- 6. Determine Final Target Path
  local target_path
  if cmd_dest_path_or_dir then
    -- User provided -d flag
    local ends_with_sep = cmd_dest_path_or_dir:match("[/]$")
    local path_type = filesystem_utils.get_path_type(cmd_dest_path_or_dir)

    if path_type == "directory" or ends_with_sep then
      -- Remove trailing slash from dir path before joining to prevent double slashes
      local dir_to_join = cmd_dest_path_or_dir:gsub("[/\\]$", "") -- Remove trailing / or \
      target_path = filesystem_utils.join_path(dir_to_join, filename)
    else
      target_path = cmd_dest_path_or_dir -- Treat as full path
    end
  elseif input_path then
    -- Path provided via table source (rare)
    target_path = input_path
  else
    -- Default path
    target_path = filesystem_utils.join_path("src", "lib", filename)
  end

  -- 7. Ensure Target Directory Exists
  local target_dir_path = target_path:match("(.+)[\\/]")
  if target_dir_path then
    local dir_ok, dir_err = filesystem_utils.ensure_dir_exists(target_dir_path)
    if not dir_ok then
      local err_msg =
        string.format("Failed to ensure target directory '%s' exists: %s", target_dir_path, dir_err or "unknown error")
      print(err_msg)
      return false, err_msg
    end
  end

  -- 8. Prepare Manifest Update (but don't save yet)
  manifest.dependencies = manifest.dependencies or {}
  manifest.dependencies[dep_name] = {
    source = source_identifier,
    path = target_path,
  }
  print(
    string.format("Preparing to add dependency '%s': source='%s', path='%s'", dep_name, source_identifier, target_path)
  )

  -- 9. Download Dependency
  print(string.format("Downloading '%s' from '%s' to '%s'...", dep_name, download_url, target_path))
  local download_ok, download_err = deps.downloader.download(download_url, target_path, verbose)

  if not download_ok then
    print(string.format("Error: Failed to download '%s'.", dep_name))
    print("  URL: " .. download_url)
    print("  Reason: " .. (download_err or "Unknown error"))
    print("  Manifest and lockfile were NOT updated.")
    -- Attempt to remove potentially partially downloaded file
    local removed, remove_err = filesystem_utils.remove_file(target_path)
    if not removed then
      print(string.format("Warning: Could not remove partially downloaded file '%s': %s", target_path, remove_err or "unknown error"))
    end
    return false, "Download failed: " .. (download_err or "Unknown error")
  end

  -- 10. Download Succeeded: Save Manifest
  print(string.format("Successfully downloaded '%s' to '%s'.", dep_name, target_path))
  local ok_save, err_save = deps.save_manifest(manifest)
  if not ok_save then
    -- Critical error: downloaded file exists, but manifest doesn't reflect it.
    local err_msg = "Critical Error: Failed to save project.lua after successful download: "
      .. (err_save or "Unknown error")
    print(err_msg)
    print("  The downloaded file exists at: " .. target_path)
    print("  The manifest (project.lua) may be inconsistent.")
    return false, err_msg
  end
  print("Updated project.lua.")

  -- 11. Update Lockfile
  local existing_lockfile_data, load_err = deps.lockfile.load_lockfile()
  if load_err and not load_err:match("Could not read lockfile") then
    -- Warn but continue, we'll create a new lockfile or overwrite based on current state.
    print("Warning: Could not load existing lockfile to merge changes: " .. tostring(load_err))
    existing_lockfile_data = nil -- Treat as if no lockfile existed
  end

  local current_lock_packages = (existing_lockfile_data and existing_lockfile_data.package) or {}

  if current_lock_packages[dep_name] then
    print(string.format("Updating existing entry for '%s' in lockfile.", dep_name))
  else
    print("Adding new entry to lockfile...")
  end

  -- Determine lockfile hash
  local lockfile_hash_string
  if commit_hash then
    lockfile_hash_string = "commit:" .. commit_hash
    print(string.format("Using commit hash '%s' for lockfile entry '%s'.", commit_hash, dep_name))
  else
    print(string.format("Calculating sha256 content hash for '%s'...", target_path))
    local content_hash, hash_err = deps.hash_utils.hash_file_sha256(target_path)
    if content_hash then
      lockfile_hash_string = "sha256:" .. content_hash
      print(string.format("Using content hash '%s' for lockfile entry '%s'.", content_hash, dep_name))
    else
      -- Non-critical warning: Lockfile entry will indicate hash failure.
      lockfile_hash_string = "hash_error:" .. (hash_err or "unknown")
      print(
        string.format(
          "Warning: Could not calculate sha256 hash for '%s': %s. Lockfile entry will reflect this.",
          target_path,
          hash_err or "unknown error"
        )
      )
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
    print(err_msg)
    print("  The manifest (project.lua) was updated, but the lockfile update failed.")
    return false, err_msg -- Return error, state is slightly inconsistent.
  end

  print("Successfully updated almd-lock.lua.")
  return true -- Entire operation successful
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
