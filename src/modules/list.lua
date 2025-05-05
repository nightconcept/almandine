--[[
  List Command Module

  Provides functionality to list all installed dependencies and their versions as recorded in the lockfile
  (almd-lock.lua) or manifest (project.lua).
]]
--

---TODO: remove this once we have a pass over this file
-- luacheck: ignore
local lockfile_utils = require("utils.lockfile")

--- Lists installed dependencies and their versions.
---@param load_manifest function Function to load the manifest.
---@param deps table Dependency table containing `printer`.
---@return boolean success True if successful, false otherwise.
---@return string|nil message Formatted list for stdout.
---@return string|nil error_message Error message for stderr.
local function list_dependencies(load_manifest, deps)
  local lockfile = lockfile_utils.load_lockfile()
  local lockfile_exists = (lockfile ~= nil)

  local dependencies = {}
  local source_description = ""

  if lockfile_exists and type(lockfile) == "table" and lockfile.dependencies then
    dependencies = lockfile.dependencies
    source_description = " (from almd-lock.lua)"
  else
    local manifest, manifest_err = load_manifest()
    if manifest_err then
      return false, nil, "Error loading project.lua: " .. tostring(manifest_err)
    elseif not manifest then
      return false, nil, "Could not find or load project.lua."
    end
    if type(manifest) == "table" and manifest.dependencies then
      dependencies = manifest.dependencies
      source_description = " (from project.lua)"
    end
  end

  local output = {}
  if next(dependencies) == nil then
    table.insert(output, "No dependencies found.")
  else
    table.insert(output, "Installed dependencies" .. source_description .. ":")
    -- Sort dependencies by name for consistent output
    local sorted_names = {}
    for name, _ in pairs(dependencies) do
      table.insert(sorted_names, name)
    end
    table.sort(sorted_names)

    for _, name in ipairs(sorted_names) do
      local dep = dependencies[name]
      local version
      if type(dep) == "table" then
        version = dep.version or (dep.tag and "tag:" .. dep.tag) or (dep.branch and "branch:" .. dep.branch) or (dep.hash and "#" .. dep.hash)
        if not version or version == "" then
          version = "(unknown source)"
        end
      elseif type(dep) == "string" then
        version = dep
      else
        version = "(unknown type)"
      end
      table.insert(output, string.format("  %s\t%s", name, version))
    end
  end
  return true, table.concat(output, "\n")
end

---
-- Prints usage/help information for the `list` command.
-- Usage: almd list
-- Lists all installed dependencies and their versions.
local function help_info()
  return [[Usage: almd list

Lists all installed dependencies and their versions.
Prioritizes almd-lock.lua if it exists, otherwise uses project.lua.
]]
end

return {
  list_dependencies = list_dependencies,
  help_info = help_info,
}
