--[[
  List Module

  Provides functionality to list all installed dependencies and their versions as recorded in the lockfile (almd-lock.lua) or manifest (project.lua).
  Implements Task 4.6: `almd list` command.
]]--

--- Lists installed dependencies and their versions.
-- @param load_manifest function Function to load the manifest.
-- @param lockfile_path string Path to the lockfile (default: "almd-lock.lua").
local function list_dependencies(load_manifest, lockfile_path)
  lockfile_path = lockfile_path or "almd-lock.lua"
  local lockfile = nil
  local lockfile_exists = false
  local file = io.open(lockfile_path, "r")
  if file then
    local chunk = file:read("*a")
    file:close()
    local f, err = load(chunk, "@"..lockfile_path, "t", {})
    if f then
      local ok, result = pcall(f)
      if ok and type(result) == "table" and result.package then
        lockfile = result
        lockfile_exists = true
      end
    end
  end

  if lockfile_exists and lockfile and lockfile.package then
    print("Installed dependencies (from lockfile):")
    for name, dep in pairs(lockfile.package) do
      local version = dep.version or (dep.hash and ("#"..dep.hash)) or "(unknown)"
      print(string.format("  %s\t%s", name, version))
    end
    return
  end

  -- Fall back to manifest if lockfile missing or invalid
  local manifest, err = load_manifest()
  if not manifest then
    print("Could not load project manifest: " .. tostring(err))
    return
  end
  local deps = manifest.dependencies or {}
  if next(deps) == nil then
    print("No dependencies found in project.lua.")
    return
  end
  print("Dependencies (from project.lua):")
  for name, source in pairs(deps) do
    local version = "(source)"
    if type(source) == "string" then
      version = source
    elseif type(source) == "table" and source.version then
      version = source.version
    end
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
  almd list
]])
end

return {
  list_dependencies = list_dependencies,
  help_info = help_info
}
