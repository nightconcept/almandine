--[[
  Filesystem Utilities

  Provides helpers for cross-platform directory creation and related filesystem tasks.
]]
--

local M = {}

--- Ensures the lib directory exists (src/lib).
-- @param sep string|nil Optional path separator override.
-- @param os_execute function|nil Optional os.execute override.
function M.ensure_lib_dir(sep, os_execute)
  sep = sep or package.config:sub(1, 1)
  os_execute = os_execute or os.execute
  local path = "src" .. sep .. "lib"
  if sep == "\\" then
    os_execute("mkdir " .. path .. " >nul 2>&1")
  else
    os_execute("mkdir -p " .. path .. " >/dev/null 2>&1")
  end
  -- Remove noisy warning, only print if directory is truly missing (optional: check existence)
end

--- Joins path segments using the correct platform separator.
-- @param ... string Path segments
-- @return string Joined path
function M.join_path(...)
  local sep = package.config:sub(1, 1)
  local args = { ... }
  return table.concat(args, sep)
end

return M
