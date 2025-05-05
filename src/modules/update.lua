--[[
  Update Command Module

  Provides functionality to update dependencies to the latest allowed version or the absolute latest
  version if the `--latest` flag is provided.
]]
--

---TODO: remove this once we have a pass over this file
-- luacheck: ignore
---@class UpdateDeps
---@field load_manifest fun(): table, string?
---@field save_manifest fun(manifest: table): boolean, string?
---@field ensure_lib_dir fun(): nil
---@field downloader table
---@field resolve_latest_version fun(name: string): string?
---@field latest boolean|nil
---@field printer table Printer utility with stdout/stderr methods.

--- Updates all dependencies in project.lua to the latest allowed version, or to the latest available if
-- `--latest` is set.
-- @param load_manifest function Function to load the manifest.
-- @param save_manifest function Function to save the manifest.
-- @param ensure_lib_dir function Function to ensure lib dir exists.
-- @param utils table Utils module (must provide .downloader).
-- @param resolve_latest_version function Function to resolve latest version for a dependency (semver or commit).
-- @param _latest boolean|nil Whether to force update to absolute latest version.
-- @param printer function|nil Optional print function for output (default: print)
-- @param deps UpdateDeps Table containing dependencies and settings.
-- @return boolean success True if successful, false otherwise.
-- @return string|nil output_message Message for stdout.
-- @return string|nil error_message Message for stderr.
local function update_dependencies(
  load_manifest,
  save_manifest,
  ensure_lib_dir,
  utils,
  resolve_latest_version,
  _latest,
  printer,
  deps
)
  local load_manifest = deps.load_manifest
  local save_manifest = deps.save_manifest
  local ensure_lib_dir = deps.ensure_lib_dir
  local utils = { downloader = deps.downloader } -- Adapt to expected structure if needed
  local resolve_latest_version = deps.resolve_latest_version
  local _latest = deps.latest
  local printer = deps.printer

  local output_messages = {}
  local error_messages = {}

  printer = printer or print
  ensure_lib_dir()
  local manifest, err = load_manifest()
  if not manifest then
    table.insert(error_messages, "Failed to load manifest: " .. (err or "Unknown error"))
    return false, nil, table.concat(error_messages, "\n")
  end
  local updated = false
  table.insert(output_messages, "Checking for updates...")
  for name, dep in pairs(manifest.dependencies or {}) do
    local dep_tbl = dep
    if type(dep) == "string" then
      dep_tbl = { url = dep }
    end
    local new_version = resolve_latest_version(name)
    if new_version and dep_tbl.version ~= new_version then
      dep_tbl.version = new_version
      local current_version_str = dep_tbl.version or "(unknown)"
      table.insert(output_messages, string.format("Updating %s from %s to %s", name, current_version_str, new_version))
      updated = true
      local url = dep_tbl.url or dep
      local out_path = dep_tbl.path or ("src/lib/" .. name .. ".lua")
      local ok, err2 = utils.downloader.download(url, out_path)
      if not ok then
        table.insert(error_messages, string.format("Error: Failed to download %s: %s", name, err2 or "unknown error"))
      else
        table.insert(output_messages, string.format(" -> Downloaded %s successfully.", name))
      end
      -- If we upgraded from a string, update the manifest entry to a table
      manifest.dependencies[name] = dep_tbl
    end
  end
  if updated then
    table.insert(output_messages, "Saving updated manifest...")
    local ok_save, err_save = save_manifest(manifest)
    if not ok_save then
      table.insert(error_messages, "Error: Failed to save manifest: " .. (err_save or "Unknown error"))
      -- Decide if this is fatal. Let's say yes for now.
      return false, table.concat(output_messages, "\n"), table.concat(error_messages, "\n")
    else
      table.insert(output_messages, "Manifest updated.")
    end
  else
    table.insert(output_messages, "All dependencies are up-to-date.")
  end

  -- Combine messages for return
  local final_output = table.concat(output_messages, "\n")
  local final_error = nil
  if #error_messages > 0 then
    final_error = table.concat(error_messages, "\n")
  end

  return true, final_output, final_error
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
  help_info = help_info,
}
