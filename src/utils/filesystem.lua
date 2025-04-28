--[[
  Filesystem Utilities

  Provides helpers for cross-platform directory creation and related filesystem tasks.
]]--

local M = {}

--- Ensures the lib directory exists (src/lib).
function M.ensure_lib_dir()
  local sep = package.config:sub(1,1)
  local path = "src" .. sep .. "lib"
  local ok
  if sep == "\\" then
    ok = os.execute("mkdir " .. path .. " >nul 2>&1")
  else
    ok = os.execute("mkdir -p " .. path .. " >/dev/null 2>&1")
  end
  -- Remove noisy warning, only print if directory is truly missing (optional: check existence)
end

return M
