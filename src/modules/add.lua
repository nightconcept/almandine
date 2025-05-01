--[[
  add
  @module add

  Provides functionality to add a dependency to the project manifest and download it to a designated directory.
]]

local filesystem_utils = require("utils.filesystem") -- Added require
local url_utils = require("utils.url") -- Require the new utility

---@class AddDeps
---@field load_manifest fun(): table, string?
---@field save_manifest fun(manifest: table): boolean, string?
---@field ensure_lib_dir fun(): nil
---@field downloader table
---@field downloader.download fun(url: string, path: string): boolean, string?
---@field hash_utils table
---@field hash_utils.hash_dependency fun(dep: string|table): string, string?
---@field lockfile table
---@field lockfile.generate_lockfile_table fun(deps: table): table
---@field lockfile.write_lockfile fun(table): boolean, string?
---@field lockfile.load_lockfile fun(): table?, string?

---@param dep_name string|nil Dependency name to add. If nil, inferred from source URL.
---@param dep_source string|table Dependency source string (URL) or table with url/path.
---@param dest_dir string|nil Optional destination directory for the installed file.
---@param deps AddDeps Table containing dependency injected functions.
---@return boolean success True if operation completed successfully.
---@return string? error Error message if operation failed.
local function add_dependency(dep_name, dep_source, cmd_dest_path_or_dir, deps)
  deps.ensure_lib_dir()
  local manifest, err = deps.load_manifest()
  if not manifest then
    print(err)
    return false, err
  end

  local input_url
  local input_path -- Path provided explicitly in dep_source table (rarely used from CLI)

  if type(dep_source) == "table" then
    input_url = dep_source.url
    input_path = dep_source.path -- Note: This is *not* the -d flag value
    if not input_url then
      return false, "Dependency source table must contain a 'url' field."
    end
  else
    input_url = dep_source
    input_path = nil
  end

  -- Determine the filename part (e.g., "shove.lua")
  local filename = input_url:match("/([^/]+)$") or dep_name .. ".lua" -- Fallback using dep_name
  if not filename or filename == "" then
    return false, "Could not determine filename from URL: " .. input_url
  end

  -- If no dep_name provided, try to infer from filename
  if not dep_name then
    local name_from_file = filename:match("^(.+)%.lua$")
    if name_from_file then
      dep_name = name_from_file
    else
      return false, "Could not infer dependency name from URL/filename: " .. input_url
    end
  end

  -- Normalize the input URL
  local base_url, commit_hash, download_url, norm_err = url_utils.normalize_github_url(input_url)
  if norm_err then
    return false, string.format("Failed to process URL '%s': %s", input_url, norm_err)
  end
  if not download_url then
    return false, string.format("Could not determine download URL for '%s'", input_url)
  end

  -- Determine the final target path for the dependency file
  local target_path
  if cmd_dest_path_or_dir then
    -- User provided -d flag
    local ends_with_sep = cmd_dest_path_or_dir:match("[/\\]$")
    local path_type = filesystem_utils.get_path_type(cmd_dest_path_or_dir)

    if path_type == "directory" or ends_with_sep then
      -- Treat as directory: join provided dir path and filename
      target_path = filesystem_utils.join_path(cmd_dest_path_or_dir, filename)
    else
      -- Treat as full file path (even if it doesn't exist yet)
      target_path = cmd_dest_path_or_dir
    end
  elseif input_path then
    -- Path was provided via table source (rare for CLI use)
    target_path = input_path
  else
    -- Default path: src/lib/<filename>
    target_path = filesystem_utils.join_path("src", "lib", filename)
  end

  -- Ensure the target directory exists (downloader might not create intermediate dirs)
  local target_dir_path = target_path:match("(.+)[\\/]") -- Extract directory part
  if target_dir_path then
    -- Use the newly added function
    local dir_ok, dir_err = filesystem_utils.ensure_dir_exists(target_dir_path)
    if not dir_ok then
      -- Report error and stop if directory creation fails
      local err_msg =
        string.format("Failed to ensure target directory '%s' exists: %s", target_dir_path, dir_err or "unknown error")
      print(err_msg)
      return false, err_msg
    end
  end

  -- Store the structured dependency info in the manifest
  manifest.dependencies = manifest.dependencies or {}
  local manifest_entry = {
    url = base_url,
    path = target_path,
  }
  if commit_hash then
    manifest_entry.hash = commit_hash -- Store GitHub commit hash if available
  end
  manifest.dependencies[dep_name] = manifest_entry

  local ok, err2 = deps.save_manifest(manifest)
  if not ok then
    print(err2)
    return false, err2
  end
  print(string.format("Added dependency '%s' to project.lua.", dep_name))

  -- Download directly to the target path
  print(string.format("Downloading %s from %s to %s...", dep_name, download_url, target_path))
  local ok3, err3 = deps.downloader.download(download_url, target_path)
  if ok3 then
    print(string.format("Downloaded %s to %s", dep_name, target_path))
  else
    print(string.format("Failed to download %s: %s", dep_name, err3))
    -- Attempt to revert manifest change on download failure?
    -- For now, we leave the manifest updated but report the error.
    return false, err3
  end

  -- Load existing lockfile to check before updating
  local existing_lockfile_data, load_err = deps.lockfile.load_lockfile()
  if load_err and not load_err:match("Could not read lockfile") then
    print("Warning: Could not load existing lockfile to check for update: " .. tostring(load_err))
    existing_lockfile_data = nil
  end

  -- Update lockfile only if it doesn't exist or the dependency isn't already in it
  if not existing_lockfile_data or not existing_lockfile_data[dep_name] then
    print("Updating lockfile...")
    -- Build resolved_deps table for lockfile
    local resolved_deps = {}
    for name, dep_info in pairs(manifest.dependencies or {}) do
      -- dep_info is now always a table { url=..., path=..., [hash=...] }
      local content_hash, hash_err
      -- ** TODO: This hash_dependency likely needs the *path* to the file, not the manifest entry **
      -- ** Current hash_utils.hash_dependency hashes the *table* representation, not file content **
      -- ** This needs adjustment in hash_utils for correct content hashing **
      content_hash, hash_err = deps.hash_utils.hash_dependency(dep_info) -- Using current flawed logic
      if not content_hash then
        print("Warning: Could not generate content hash for " .. name .. ": " .. tostring(hash_err))
        content_hash = "unknown"
      end
      resolved_deps[name] = {
        -- Use the base URL from the manifest entry as the source identifier in the lockfile
        source = dep_info.url,
        hash = content_hash, -- This should be the content hash
        -- We could add commit = dep_info.hash here if needed in lockfile
      }
    end
    local lockfile_table = deps.lockfile.generate_lockfile_table(resolved_deps)
    local ok_lock, err_lock = deps.lockfile.write_lockfile(lockfile_table)
    if ok_lock then
      print("Updated lockfile: almd-lock.lua")
    else
      print("Failed to update lockfile: " .. tostring(err_lock))
    end
  else
    print(string.format("Lockfile already contains entry for '%s', skipping update.", dep_name))
  end

  return true
end

---Prints usage/help information for the `add` command.
---Usage: almd add <source> [-d <dir>] [-n <dep_name>]
---@return string Usage string for the add command.
local function help_info()
  return [[
Usage: almd add <source> [-d <dir>] [-n <dep_name>]

Options:
  -d <dir>     Destination directory for the installed file
  -n <name>    Name of the dependency (optional, inferred from URL if not provided)

Example:
  almd add https://example.com/lib.lua
  almd add https://example.com/lib.lua -d src/lib/custom
  almd add https://example.com/lib.lua -n mylib
]]
end

return {
  add_dependency = add_dependency,
  help_info = help_info,
}
