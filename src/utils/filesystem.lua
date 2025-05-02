--[[
  Filesystem Utilities

  Provides helpers for cross-platform directory creation and related filesystem tasks.
]]
--

local M = {}

-- Attempt to load LuaFileSystem. Handle error if not found.
local success, lfs = pcall(require, "lfs")
if not success then
  -- Fallback or error handling if lfs is critical
  print("Warning: LuaFileSystem (lfs) not found. Some path checks might be limited.")
  lfs = nil
end

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

---
-- Ensures a given directory path exists, creating intermediate directories if needed.
-- @param dir_path string The full path to the directory.
-- @return boolean success True if the directory exists or was created successfully.
-- @return string|nil error_message Error message if creation failed.
function M.ensure_dir_exists(dir_path)
  if not dir_path or dir_path == "" then
    return false, "Directory path cannot be empty"
  end

  -- Platform-specific separator
  local sep = package.config:sub(1, 1)

  -- Normalize path separators for the current OS
  if sep == "\\" then
    dir_path = dir_path:gsub("/", "\\")
  else
    dir_path = dir_path:gsub("\\", "/")
  end

  -- Check if it exists and is a directory using os.rename trick
  -- This is more portable than trying to parse `ls` or `dir` output.
  -- Renaming to itself should succeed only if it exists and is a directory.
  local exists = os.rename(dir_path, dir_path)
  if exists then
    return true -- Already exists and is a directory
  end

  -- Attempt to create the directory recursively
  -- Need to handle potential errors if path exists as a file
  local command
  if sep == "\\" then
    -- On Windows, `mkdir` doesn't have a `-p` equivalent built-in, but
    -- it will create intermediate directories if the path doesn't exist.
    -- We suppress errors as it might fail if parts already exist.
    command = string.format('mkdir "%s" >nul 2>&1', dir_path)
  else
    -- On Unix-like systems, `mkdir -p` creates parent directories as needed
    -- and doesn't error if the directory already exists.
    command = string.format('mkdir -p "%s"', dir_path)
  end

  os.execute(command) -- Execute the constructed command

  -- Verify creation by checking existence again
  if os.rename(dir_path, dir_path) then
    return true -- Directory now exists
  else
    -- If creation command ran (code might be 0 even on failure depending on shell/case)
    -- and it still doesn't exist, report failure.
    return false, "Failed to create directory: " .. dir_path .. " (command executed, but dir not found after)"
  end
end

---
-- Gets information about a path (type: file, directory, other, or nil if not found).
-- Uses lfs if available for better accuracy.
-- @param path string The path to check.
-- @return string|nil Type of the path ("file", "directory", "other") or nil if not found/error.
function M.get_path_type(path)
  if not path then
    return nil
  end

  if lfs and lfs.attributes then
    -- Use lfs for reliable type checking
    local mode = lfs.attributes(path, "mode")
    if mode == "directory" then
      return "directory"
    elseif mode == "file" then
      return "file"
    elseif mode then
      return "other" -- Could be symlink, device, etc.
    else
      return nil -- Path does not exist or error accessing
    end
  else
    -- Fallback without lfs: less reliable, only checks for directory existence
    -- via the os.rename trick. Cannot reliably distinguish files.
    if os.rename(path, path) then
      return "directory" -- It exists and rename worked, likely a directory.
    else
      -- Could be a file, or not exist, or permissions error. Cannot be sure.
      return nil
    end
  end
end

---
-- Attempts to remove a file.
-- @param file_path string The path to the file to remove.
-- @return boolean success True if the file was removed successfully or did not exist.
-- @return string|nil error_message Error message if removal failed.
function M.remove_file(file_path)
  if not file_path then
    return false, "File path cannot be nil"
  end
  -- os.remove returns nil + error message on failure
  local ok, err = os.remove(file_path)
  if ok then
    return true -- Successfully removed
  elseif err:match("No such file or directory") then
    return true -- File didn't exist, which is fine for cleanup
  else
    return false, err -- Return the actual error message from os.remove
  end
end

return M
