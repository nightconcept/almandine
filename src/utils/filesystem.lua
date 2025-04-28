--[[
  Filesystem Utilities

  Provides helpers for cross-platform directory creation and related filesystem tasks.
]]
--

local M = {}

--- Ensures the lib directory exists (src/lib).
function M.ensure_lib_dir()
  local sep = package.config:sub(1, 1)
  local path = "src" .. sep .. "lib"
  if sep == "\\" then
    os.execute("mkdir " .. path .. " >nul 2>&1")
  else
    os.execute("mkdir -p " .. path .. " >/dev/null 2>&1")
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
