--[[
  Version Utilities

  Provides helpers for parsing, comparing, and checking Lua version constraints.
]]
--

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
  if a[1] ~= b[1] then
    return a[1] - b[1]
  end
  if a[2] ~= b[2] then
    return a[2] - b[2]
  end
  return (a[3] or 0) - (b[3] or 0)
end

--- Checks if the current Lua version satisfies a constraint string.
-- @param constraint string Constraint (e.g., ">= 5.1")
-- @param lua_version_str string|nil Override for _VERSION (for testing)
-- @return boolean
function M.lua_version_satisfies(constraint, lua_version_str)
  if not constraint or constraint == "" then
    return true
  end
  -- Use robust regex for constraints
  local op, ver = constraint:match("^%s*([<>]=?|=)%s*(%d+%.%d+)%s*$")
  if not op or not ver then
    return false
  end
  local req_major, req_minor = ver:match("(%d+)%.(%d+)")
  req_major, req_minor = tonumber(req_major), tonumber(req_minor)
  local cur_major, cur_minor = (lua_version_str or _VERSION):match("Lua (%d+)%.(%d+)")
  cur_major, cur_minor = tonumber(cur_major), tonumber(cur_minor)
  local result
  if not (cur_major and cur_minor and req_major and req_minor) then
    result = false
  elseif op == ">=" then
    result = cur_major > req_major or (cur_major == req_major and cur_minor >= req_minor)
  elseif op == ">" then
    result = cur_major > req_major or (cur_major == req_major and cur_minor > req_minor)
  elseif op == "<=" then
    result = cur_major < req_major or (cur_major == req_major and cur_minor <= req_minor)
  elseif op == "<" then
    result = cur_major < req_major or (cur_major == req_major and cur_minor < req_minor)
  elseif op == "=" then
    result = cur_major == req_major and cur_minor == req_minor
  else
    result = false
  end
  return result
end

--- Checks if the current project manifest's Lua version constraint is satisfied.
-- @param load_manifest function Function to load the manifest.
-- @param lua_version_str string|nil Override for _VERSION (for testing)
-- @return boolean True if satisfied, otherwise exits the program.
function M.check_lua_version(load_manifest, lua_version_str)
  local manifest = load_manifest()
  if not manifest then
    return true
  end
  if manifest.lua then
    if not M.lua_version_satisfies(manifest.lua, lua_version_str) then
      io.stderr:write(
        string.format(
          "Error: Project requires Lua version %s, but running %s\n",
          manifest.lua,
          lua_version_str or _VERSION
        )
      )
      os.exit(1)
    end
  end
  return true
end

--- Returns the Almandine CLI version string from src/almd_version.lua
function M.get_version()
  local ok, v = pcall(require, "almd_version")
  if ok and type(v) == "string" then
    return v
  end
  return "(unknown)"
end

return M
