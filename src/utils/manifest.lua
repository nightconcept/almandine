--[[
  Manifest Loader Utility

  Provides functions to safely load the project manifest (project.lua) with validation.
]]--

local manifest = {}

--- Safely load the project manifest.
-- @param path string Path to the manifest file (default: "project.lua").
-- @return table|nil, string|nil Manifest table or nil and error message.
function manifest.safe_load_project_manifest(path)
  path = path or "project.lua"
  local chunk, err = loadfile(path)
  if not chunk then return nil, err end
  local ok, result = pcall(chunk)
  if not ok then return nil, result end
  if type(result) ~= "table" then
    return nil, "Manifest must return a table"
  end
  return result, nil
end

return manifest
