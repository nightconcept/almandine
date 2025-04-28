--[[
  Update Command Module

  Provides functionality to update dependencies to the latest allowed version or the absolute latest
  version if the `--latest` flag is provided.
]]--

--- Updates all dependencies in project.lua to the latest allowed version, or to the latest available if
-- `--latest` is set.
-- @param load_manifest function Function to load the manifest.
-- @param save_manifest function Function to save the manifest.
-- @param ensure_lib_dir function Function to ensure lib dir exists.
-- @param utils table Utils module (must provide .downloader).
-- @param resolve_latest_version function Function to resolve latest version for a dependency (semver or commit).
-- @param _latest boolean|nil Whether to force update to absolute latest version.
local function update_dependencies(load_manifest, save_manifest, ensure_lib_dir, utils, resolve_latest_version, _latest)
  ensure_lib_dir()
  local manifest, err = load_manifest()
  if not manifest then print(err) return end
  local updated = false
  for name, dep in pairs(manifest.dependencies or {}) do
    local dep_tbl = dep
    if type(dep) == "string" then
      dep_tbl = { url = dep }
    end
    local new_version = resolve_latest_version(name)
    if new_version and dep_tbl.version ~= new_version then
      dep_tbl.version = new_version
      updated = true
      local url = dep_tbl.url or dep
      local out_path = dep_tbl.path or ("src/lib/" .. name .. ".lua")
      local ok, err2 = utils.downloader.download(url, out_path)
      if not ok then
        print(string.format(
          "Failed to download %s: %s",
          name,
          err2 or "unknown error"
        ))
      else
        print(string.format(
          "Updating %s from %s to %s",
          name,
          dep_tbl.version or "(unknown)",
          new_version
        ))
      end
      -- If we upgraded from a string, update the manifest entry to a table
      manifest.dependencies[name] = dep_tbl
    end
  end
  if updated then
    save_manifest(manifest)
  end
end

---
-- Prints usage/help information for the `update` command.
-- Usage: almd update [--latest]
-- Updates dependencies to the latest allowed version, or to the absolute latest if --latest is specified.
local function help_info()
  print([[
Usage: almd update [--latest]

Updates all dependencies to the latest allowed version, or to the absolute latest if --latest is specified.
Example:
  almd update
  almd update --latest
]])
end

return {
  update_dependencies = update_dependencies,
  help_info = help_info
}
