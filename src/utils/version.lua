--[[
  Version Utilities

  Provides helpers for parsing, comparing, and checking Lua version constraints.
]]--

local M = {}

--- Parses a Lua version string to numeric major, minor, patch.
-- @param ver_str string Version string (e.g., "5.1.4")
-- @return number, number, number Major, minor, patch
function M.parse_lua_version(ver_str)
  local major, minor, patch = ver_str:match("^(%d+)%.(%d+)%.?(%d*)")
  return tonumber(major), tonumber(minor), tonumber(patch) or 0
end

--- Compares two version tables {major, minor, patch}.
-- @param a table First version
-- @param b table Second version
-- @return number Negative if a < b, positive if a > b, 0 if equal
function M.compare_lua_versions(a, b)
  if a[1] ~= b[1] then return a[1] - b[1] end
  if a[2] ~= b[2] then return a[2] - b[2] end
  return (a[3] or 0) - (b[3] or 0)
end

--- Checks if the current Lua version satisfies a constraint string.
-- @param constraint string Constraint (e.g., ">= 5.1")
-- @return boolean
function M.lua_version_satisfies(constraint)
  if not constraint or constraint == "" then return true end
  local op, ver = constraint:match("^([<>]=?|=)%s*(%d+%.%d+)")
  if not op or not ver then return true end
  local req_major, req_minor = ver:match("(%d+)%.(%d+)")
  req_major, req_minor = tonumber(req_major), tonumber(req_minor)
  local cur_major, cur_minor = _VERSION:match("Lua (%d+)%.(%d+)")
  cur_major, cur_minor = tonumber(cur_major), tonumber(cur_minor)
  if not (cur_major and cur_minor and req_major and req_minor) then return true end
  if op == ">=" then
    return cur_major > req_major or (cur_major == req_major and cur_minor >= req_minor)
  elseif op == ">" then
    return cur_major > req_major or (cur_major == req_major and cur_minor > req_minor)
  elseif op == "<=" then
    return cur_major < req_major or (cur_major == req_major and cur_minor <= req_minor)
  elseif op == "<" then
    return cur_major < req_major or (cur_major == req_major and cur_minor < req_minor)
  elseif op == "=" then
    return cur_major == req_major and cur_minor == req_minor
  end
  return true
end

--- Checks if the current project manifest's Lua version constraint is satisfied.
-- @param load_manifest function Function to load the manifest.
-- @return boolean True if satisfied, otherwise exits the program.
function M.check_lua_version(load_manifest)
  local manifest, err = load_manifest()
  if not manifest then return true end
  if manifest.lua then
    if not M.lua_version_satisfies(manifest.lua) then
      io.stderr:write(string.format(
        "Error: Project requires Lua version %s, but running %s\n",
        manifest.lua, _VERSION
      ))
      os.exit(1)
    end
  end
  return true
end

return M
