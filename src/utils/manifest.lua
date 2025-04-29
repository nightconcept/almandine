--[[
  Manifest Loader Utility

  Provides functions to safely load the project manifest (project.lua) with validation.
]]
--

local manifest = {}

--- Safely load the project manifest.
-- @param path string Path to the manifest file (default: "project.lua").
-- @return table|nil, string|nil Manifest table or nil and error message.
function manifest.safe_load_project_manifest(path)
  path = path or "project.lua"
  local chunk, err = loadfile(path)
  if not chunk then
    return nil, err
  end
  local ok, result = pcall(chunk)
  if not ok then
    return nil, result
  end
  if type(result) ~= "table" then
    return nil, "Manifest must return a table"
  end
  return result, nil
end

--- Saves the project manifest to project.lua.
-- @param manifest_table table Manifest table to save.
-- @return boolean, string True on success, false and error message on failure.
-- @usage
--   local ok, err = manifest.save_manifest(tbl)
function manifest.save_manifest(manifest_table)
  local file, err = io.open("project.lua", "w")
  if not file then
    return false, "Could not write project.lua: " .. tostring(err)
  end
  file:write("return {\n")
  file:write(string.format('  name = "%s",\n', manifest_table.name or ""))
  file:write(string.format('  type = "%s",\n', manifest_table.type or ""))
  file:write(string.format('  version = "%s",\n', manifest_table.version or ""))
  file:write(string.format('  license = "%s",\n', manifest_table.license or ""))
  file:write(string.format('  description = "%s",\n', manifest_table.description or ""))
  file:write("  scripts = {\n")
  for k, v in pairs(manifest_table.scripts or {}) do
    file:write(string.format('    [%q] = "%s",\n', k, v))
  end
  file:write("  },\n")
  file:write("  dependencies = {\n")
  for k, v in pairs(manifest_table.dependencies or {}) do
    if type(v) == "table" then
      local url = v.url or ""
      local path = v.path or ""
      -- Escape backslashes in path for Lua syntax
      path = path:gsub("\\", "\\\\")
      file:write(string.format('    [%q] = { url = "%s", path = "%s" },\n', k, url, path))
    else
      file:write(string.format('    [%q] = "%s",\n', k, v))
    end
  end
  file:write("  }\n}\n")
  file:close()
  return true, nil
end

return manifest
