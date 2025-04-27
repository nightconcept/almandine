--[[
  Manifest Loader for Snowdrop

  Provides a secure loader for project.lua manifest files, ensuring only a single table literal is accepted.
  Prevents arbitrary code execution by using an empty environment and strict pattern matching.
]]--

local manifest_loader = {}

--- Loads the project manifest from a file with security checks.
-- Only allows a single table literal, no code execution.
-- @param path string Path to the manifest file (default: "project.lua")
-- @return table|nil, string|nil Manifest table or nil and error message.
function manifest_loader.safe_load_project_manifest(path)
  path = path or "project.lua"
  local file, err = io.open(path, "r")
  if not file then return nil, "Could not open " .. path .. ": " .. tostring(err) end
  local content = file:read("*a")
  file:close()
  -- Remove comments (block and line)
  content = content:gsub("%-%-%[%[.-%]%]--", "")
  content = content:gsub("%-%-.-\n", "\n")
  -- Only allow 'return' at the start, followed by a table literal
  local tbl_code = content:match("^%s*return%s*(%b{})%s*$")
  if not tbl_code then
    return nil, path .. " must contain only a single table literal (no code execution allowed)"
  end
  local f, perr
  if _VERSION == "Lua 5.1" or _VERSION:match("LuaJIT") then
    f, perr = loadstring("return " .. tbl_code, path)
    if f then setfenv(f, {}) end
  else
    f, perr = load("return " .. tbl_code, path, "t", {})
  end
  if not f then
    return nil, "Syntax error in " .. path .. ": " .. tostring(perr)
  end
  local ok, result = pcall(f)
  if not ok then
    return nil, "Error loading " .. path .. ": " .. tostring(result)
  end
  if type(result) ~= "table" then
    return nil, path .. " must return a table"
  end
  return result, nil
end

return manifest_loader
