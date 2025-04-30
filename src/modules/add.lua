--[[
  add
  @module add

  Provides functionality to add a dependency to the project manifest and download it to a designated directory.
]]

-- local filesystem_utils = require("utils.filesystem")
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
local function add_dependency(dep_name, dep_source, _dest_dir, deps)
  deps.ensure_lib_dir()
  local manifest, err = deps.load_manifest()
  if not manifest then
    print(err)
    return false, err
  end

  -- If no dep_name provided, try to infer from URL
  if not dep_name then
    if type(dep_source) == "string" then
      local url = dep_source
      -- Try to extract name from URL
      local name = url:match("/([^/]+)%.lua$")
      if name then
        dep_name = name
      else
        return false, "Could not infer dependency name from URL"
      end
    else
      return false, "Dependency name must be provided when source is a table"
    end
  end

  -- If dep_source is a table, extract URL and path
  local url, out_path
  if type(dep_source) == "table" then
    url = dep_source.url
    out_path = dep_source.path or dep_name .. ".lua"
  else
    url = dep_source
    out_path = dep_name .. ".lua"
  end

  -- Normalize GitHub URLs using the utility function
  local source_url, download_url, norm_err = url_utils.normalize_github_url(url)
  if norm_err then
    return false, "Failed to normalize URL: " .. norm_err
  end
  -- Store the original (or potentially normalized source) URL in the manifest
  if type(dep_source) == "table" then
    manifest.dependencies[dep_name] = { url = source_url, path = dep_source.path }
  else
    manifest.dependencies[dep_name] = source_url
  end

  local ok, err2 = deps.save_manifest(manifest)
  if not ok then
    print(err2)
    return false, err2
  end
  print(string.format("Added dependency '%s' to project.lua.", dep_name))

  -- Download using the potentially raw URL
  local ok3, err3 = deps.downloader.download(download_url, out_path)
  if ok3 then
    print(string.format("Downloaded %s to %s", dep_name, out_path))
  else
    print(string.format("Failed to download %s: %s", dep_name, err3))
    return false, err3
  end

  -- Load existing lockfile to check before updating
  local existing_lockfile_data, load_err = deps.lockfile.load_lockfile()
  if load_err and not load_err:match("Could not read lockfile") then -- Ignore "not found" error, treat as empty
    print("Warning: Could not load existing lockfile to check for update: " .. tostring(load_err))
    -- Proceed to update even if loading failed (except for 'not found')
    existing_lockfile_data = nil -- Treat error as needing update check
  end

  -- Update lockfile only if it doesn't exist or the dependency isn't already in it
  if not existing_lockfile_data or not existing_lockfile_data[dep_name] then
    print("Updating lockfile...") -- Indicate action
    -- Build resolved_deps table for lockfile with proper hashes
    local resolved_deps = {}
    for name, dep in pairs(manifest.dependencies or {}) do
      local lock_dep_entry = type(dep) == "table" and dep or { url = dep }
      local hash, hash_err = deps.hash_utils.hash_dependency(dep)
      if not hash then
        print("Warning: Could not generate hash for " .. name .. ": " .. tostring(hash_err))
        hash = "unknown" -- Don't use URL as fallback anymore
      end
      resolved_deps[name] = {
        hash = hash,
        source = lock_dep_entry.url or tostring(dep),
      }
    end
    local lockfile_table = deps.lockfile.generate_lockfile_table(resolved_deps)
    local ok_lock, err_lock = deps.lockfile.write_lockfile(lockfile_table)
    if ok_lock then
      print("Updated lockfile: almd-lock.lua")
    else
      print("Failed to update lockfile: " .. tostring(err_lock))
      -- Note: The add operation succeeded overall, but lockfile update failed.
    end
  else
    print(string.format("Lockfile already contains entry for '%s', skipping update.", dep_name))
  end

  return true -- Return true because the dependency was added/downloaded successfully
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
