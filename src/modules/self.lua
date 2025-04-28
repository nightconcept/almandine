--[[
  Self-management commands for Almandine Package Manager

  Cross-platform (POSIX and Windows) implementation for self-uninstall and future self-update features.
  This module provides removal of CLI wrapper scripts and the CLI Lua folder, working on both Unix-like and Windows systems.
]]--

--- Recursively delete a directory and its contents (cross-platform: POSIX and Windows)
-- @param path [string] Directory path to delete
-- @return [boolean, string?] True if successful, or false and error message
local function rmdir_recursive(path)
  local is_windows = package.config:sub(1,1) == '\\'
  local cmd
  if is_windows then
    -- Windows: use rmdir /s /q
    cmd = string.format('rmdir /s /q "%s"', path)
  else
    -- POSIX: use rm -rf
    cmd = string.format('rm -rf %q', path)
  end
  local ok = os.execute(cmd)
  if ok == 0 or ok == true then
    return true
  else
    return false, 'Failed to remove directory: ' .. path
  end
end

--- Remove wrapper scripts and Lua CLI folder.
-- @return [boolean, string?] True if successful, or false and error message
local function uninstall_self()
  local errors = {}
  -- Remove wrapper scripts
  local wrappers = { "install/almd.sh", "install/almd.bat", "install/almd.ps1" }
  for _, script in ipairs(wrappers) do
    local ok = os.remove(script)
    if not ok then
      table.insert(errors, "Failed to remove " .. script)
    end
  end
  -- Remove src/ folder (all CLI code)
  local ok, err = rmdir_recursive("src")
  if not ok then
    table.insert(errors, "Failed to remove src/: " .. (err or "unknown error"))
  end
  if #errors > 0 then
    return false, table.concat(errors, "\n")
  end
  return true
end

return {
  uninstall_self = uninstall_self
}
