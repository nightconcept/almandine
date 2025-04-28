--[[
  List Command Module

  Provides functionality to list all installed dependencies and their versions as recorded in the lockfile
  (almd-lock.lua) or manifest (project.lua).
]]--

--- Lists installed dependencies and their versions.
-- @param load_manifest function Function to load the manifest.
-- @param load_lockfile function Function to load the lockfile.
local function list_dependencies(load_manifest, load_lockfile)
  local lockfile = nil
  local lockfile_exists = false
  if type(load_lockfile) == "function" then
    lockfile = load_lockfile()
    lockfile_exists = lockfile ~= nil
  end
  local dependencies = {}
  if lockfile_exists and type(lockfile) == "table" and lockfile.dependencies then
    dependencies = lockfile.dependencies
  else
    local manifest = load_manifest()
    if type(manifest) == "table" and manifest.dependencies then
      dependencies = manifest.dependencies
    end
  end
  if next(dependencies) == nil then
    print("No dependencies found.")
    return
  end
  print("Installed dependencies:")
  for name, dep in pairs(dependencies) do
    local version = dep.version or (dep.hash and "#" .. dep.hash) or "(unknown)"
    print(string.format("  %s\t%s", name, version))
  end
end

---
-- Prints usage/help information for the `list` command.
-- Usage: almd list
-- Lists all installed dependencies and their versions.
local function help_info()
  print([[\nUsage: almd list

Lists all installed dependencies and their versions as recorded in the lockfile or project.lua.
Example:
  almd list]])
end

return {
  list_dependencies = list_dependencies,
  help_info = help_info
}
