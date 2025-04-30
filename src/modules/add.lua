--[[
  add
  @module add

  Provides functionality to add a dependency to the project manifest and download it to a designated directory.
]]

-- local filesystem_utils = require("utils.filesystem")

--- Normalize GitHub URLs by converting blob URLs to raw URLs.
--- @param url string The URL to normalize
--- @return string normalized_url The normalized URL
--- @return string download_url The URL to use for downloading
local function normalize_github_url(url)
  -- Check if this is a GitHub blob URL
  -- Correctly capture username, repo, commit, and path directly from the URL match
  local username, repo, commit, path = url:match("^https://github%.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)$")
  if username then -- Check if the match was successful and captured groups are not nil
    -- Convert to raw URL
    local raw_url = string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", username, repo, commit, path)
    return url, raw_url
  end
  -- If not a GitHub blob URL, use as-is
  return url, url
end

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

  -- Normalize GitHub URLs
  local source_url, download_url = normalize_github_url(url)
  if not download_url then
    return false, "Failed to normalize URL: " .. (source_url or "")
  end
  manifest.dependencies[dep_name] = dep_source

  local ok, err2 = deps.save_manifest(manifest)
  if not ok then
    print(err2)
    return false, err2
  end
  print(string.format("Added dependency '%s' to project.lua.", dep_name))

  -- Download using the raw URL
  local ok3, err3 = deps.downloader.download(download_url, out_path)
  if ok3 then
    print(string.format("Downloaded %s to %s", dep_name, out_path))
  else
    print(string.format("Failed to download %s: %s", dep_name, err3))
    return false, err3
  end

  -- Generate and write lockfile after successful add
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
