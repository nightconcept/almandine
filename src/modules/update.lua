--[[
  Update Module

  Provides functionality to update dependencies to the latest allowed version or the absolute latest version if the `--latest` flag is provided.
  Implements Task 4.4 from TASK.md.
]]--

--- Updates all dependencies in project.lua to the latest allowed version, or to the latest available if `--latest` is set.
-- @param load_manifest function Function to load the manifest.
-- @param save_manifest function Function to save the manifest.
-- @param ensure_lib_dir function Function to ensure lib dir exists.
-- @param utils table Utils module.
-- @param resolve_latest_version function Function to resolve latest version for a dependency (semver or commit).
-- @param latest boolean Whether to force update to absolute latest version.
local function update_dependencies(load_manifest, save_manifest, ensure_lib_dir, utils, resolve_latest_version, latest)
  ensure_lib_dir()
  local manifest, err = load_manifest()
  if not manifest then print(err) return end
  manifest.dependencies = manifest.dependencies or {}
  local updated = false
  for name, source in pairs(manifest.dependencies) do
    local new_version, new_url = resolve_latest_version(name, source, latest)
    if new_version and new_url and new_url ~= source then
      manifest.dependencies[name] = new_url
      print(string.format("Updated %s to %s", name, new_version))
      updated = true
    else
      print(string.format("%s is up to date", name))
    end
    local out_path
    if new_url or source then
      local filesystem_utils = require("utils.filesystem")
      out_path = filesystem_utils.join_path("src", "lib", name .. ".lua")
    end
    local ok, err2 = utils.downloader.download(new_url or source, out_path)
    if ok then
      print(string.format("Downloaded %s to %s", name, out_path))
    else
      print(string.format("Failed to download %s: %s", name, err2))
    end
  end
  if updated then
    local ok, err2 = save_manifest(manifest)
    if not ok then print(err2) end
  end
end

---
-- Prints usage/help information for the `update` command.
-- Usage: almd update [--latest]
-- Updates dependencies to the latest allowed or absolute latest version.
local function help_info()
  print([[\nUsage: almd update [--latest]

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
