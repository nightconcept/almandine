--[[
  Self Command Module

  Implementation for self-uninstall and future self-update features.
  This module provides removal of CLI wrapper scripts and the CLI Lua folder.
]]
--

local M = {}

--- Recursively delete a directory and its contents (cross-platform: POSIX and Windows)
-- @param path [string] Directory path to delete
-- @param executor [function?] Optional. Function to use for executing shell commands (default: os.execute)
-- @return [boolean, string?] True if successful, or false and error message
function M.rmdir_recursive(path, executor)
  executor = executor or os.execute
  local is_windows = package.config:sub(1, 1) == "\\"
  local cmd
  if is_windows then
    cmd = string.format('rmdir /s /q "%s"', path)
  else
    cmd = string.format("rm -rf %q", path)
  end
  local ok = executor(cmd)
  -- os.execute returns true/0 on success, or nonzero/nil on failure
  if ok == 0 or ok == true then
    return true
  else
    return false, "Failed to remove directory: " .. path
  end
end

--- Remove wrapper scripts and Lua CLI folder.
-- @param executor [function?] Optional. Function to use for executing shell commands (default: os.execute)
-- @return [boolean, string?] True if successful, or false and error message
function M.uninstall_self(executor)
  -- Remove wrapper scripts from known install locations
  local is_windows = package.config:sub(1, 1) == "\\"
  local install_prefixes
  local wrappers = { "almd", "almd.sh", "almd.bat", "almd.ps1" }
  if is_windows then
    local localappdata = os.getenv("LOCALAPPDATA") or ""
    local userprofile = os.getenv("USERPROFILE") or ""
    install_prefixes = {
      localappdata .. "\\almd",
      localappdata .. "\\Programs\\almd",
      userprofile .. "\\.almd",
      userprofile .. "\\AppData\\Local\\almd",
      "C:\\Program Files\\almd",
      "C:\\almd",
    }
  else
    install_prefixes = {
      os.getenv("HOME") .. "/.local/bin",
      os.getenv("HOME") .. "/.almd/install",
      os.getenv("HOME") .. "/.almd",
      "/usr/local/bin",
    }
  end
  for _, prefix in ipairs(install_prefixes) do
    for _, script in ipairs(wrappers) do
      local sep = is_windows and "\\" or "/"
      local path = prefix .. sep .. script
      os.remove(path)
    end
  end
  -- Remove src/ folder from main install dir
  local cli_dir
  if is_windows then
    cli_dir = (os.getenv("LOCALAPPDATA") or "") .. "\\almd\\src"
    if not require("lfs").attributes(cli_dir) then
      cli_dir = (os.getenv("USERPROFILE") or "") .. "\\.almd\\src"
    end
  else
    cli_dir = os.getenv("HOME") .. "/.almd/src"
  end
  if require("lfs").attributes(cli_dir) then
    M.rmdir_recursive(cli_dir, executor)
  end
  return true
end

--- Returns the absolute path to the install root (directory containing this script)
-- Works for both CLI and test runner
local function get_install_root()
  -- Try debug.getinfo first (works for most Lua runners)
  local info = debug.getinfo(1, "S")
  local source = info and info.source or ""
  local path
  if source:sub(1, 1) == "@" then
    path = source:sub(2)
  elseif arg and arg[0] then
    path = arg[0]
  end
  if not path then
    return "."
  end
  -- Remove trailing filename (e.g. /src/modules/self.lua)
  path = path:gsub("[\\/][^\\/]-$", "")
  -- If in /src/modules, move up two dirs to install root
  if path:match("[\\/]modules$") then
    path = path:gsub("[\\/]modules$", "")
    path = path:gsub("[\\/]src$", "")
  end
  return path
end

--- Atomically self-update the CLI from the latest GitHub release.
-- Downloads, extracts, backs up, and atomically replaces the install tree.
-- Only deletes backup if new version is fully extracted and ready.
-- @return [boolean, string?] True if successful, or false and error message
function M.self_update()
  local is_windows = package.config:sub(1, 1) == "\\"
  local install_root = get_install_root()
  local join = function(...) -- join paths with correct sep
    local sep = is_windows and "\\" or "/"
    local args = { ... }
    local out = args[1] or ""
    for i = 2, #args do
      if out:sub(-1) ~= sep then
        out = out .. sep
      end
      local seg = args[i]
      if seg:sub(1, 1) == sep then
        seg = seg:sub(2)
      end
      out = out .. seg
    end
    return out
  end

  -- Utility: check if file or directory exists
  local function path_exists(path)
    local f = io.open(path, "r")
    if f then
      f:close()
      return true
    end
    return false
  end

  -- Helper: download file (wget/curl)
  local downloader = require("utils.downloader")
  local function download(url, out)
    return downloader.download(url, out)
  end

  -- Helper: run shell command
  local function shell(cmd)
    local ok = os.execute(cmd)
    return ok == 0 or ok == true
  end

  -- Set up copy commands for cross-platform compatibility
  local cp, xcopy
  if is_windows then
    cp = "copy"
    xcopy = "xcopy"
  else
    cp = "cp -f"
    xcopy = "cp -r"
  end

  -- Step 1: Fetch latest tag
  local tag_url = "https://api.github.com/repos/nightconcept/almandine/tags?per_page=1"
  local zip_url, tag

  local tmp_dir = is_windows and os.getenv("TEMP") or "/tmp"
  local uuid = tostring(os.time()) .. tostring(math.random(10000, 99999))
  local work_dir = tmp_dir .. (is_windows and "\\almd_update_" or "/almd_update_") .. uuid
  local tag_file = work_dir .. (is_windows and "\\tag.json" or "/tag.json")
  os.execute(
    (is_windows and "mkdir " or "mkdir -p ") .. work_dir .. (is_windows and " >NUL 2>&1" or " >/dev/null 2>&1")
  )
  local ok, err = download(tag_url, tag_file)
  if not ok then
    return false, "Failed to fetch latest release info: " .. (err or "unknown error")
  end
  local tag_data = io.open(tag_file, "r")
  if not tag_data then
    return false, "Could not read tag file"
  end
  local tag_json = tag_data:read("*a")
  tag_data:close()
  tag = tag_json:match('"name"%s*:%s*"([^"]+)"')
  if not tag then
    return false, "Could not parse latest tag from GitHub API"
  end
  zip_url = "https://github.com/nightconcept/almandine/archive/refs/tags/" .. tag .. ".zip"

  -- Step 2: Download zip
  local zip_path = work_dir .. (is_windows and "\\almd.zip" or "/almd.zip")
  ok, err = download(zip_url, zip_path)
  if not ok then
    return false, "Failed to download release zip: " .. (err or "unknown error")
  end
  -- Step 3: Extract zip
  local extract_dir = work_dir .. (is_windows and "\\extract" or "/extract")
  os.execute(
    (is_windows and "mkdir " or "mkdir -p ") .. extract_dir .. (is_windows and " >NUL 2>&1" or " >/dev/null 2>&1")
  )
  local unzip_cmd = is_windows
      and (
        "powershell -Command \"Add-Type -A 'System.IO.Compression.FileSystem'; "
        .. "[IO.Compression.ZipFile]::ExtractToDirectory('"
        .. zip_path
        .. "', '"
        .. extract_dir
        .. "')\""
      ) -- luacheck: ignore 121
    or ("unzip -q -o '" .. zip_path .. "' -d '" .. extract_dir .. "'")
  if not shell(unzip_cmd .. (is_windows and " >NUL 2>&1" or " >/dev/null 2>&1")) then
    return false, "Failed to extract release zip"
  end
  -- Step 4: Find extracted folder
  local extracted = extract_dir .. (is_windows and ("\\almandine-" .. tag) or ("/almandine-" .. tag))
  local extracted_v = extract_dir .. (is_windows and ("\\almandine-v" .. tag) or ("/almandine-v" .. tag))
  local main_lua_path = extracted .. "/src/main.lua"
  local main_lua_v_path = extracted_v .. "/src/main.lua"
  local file_handle = io.open(main_lua_path) or io.open(main_lua_v_path)
  local final_dir
  if file_handle then
    file_handle:close()
    final_dir = io.open(main_lua_path) and extracted or extracted_v
  else
    final_dir = nil
  end
  if not final_dir then
    return false, "Could not find extracted CLI source in zip"
  end

  -- Step 5: Backup current install tree (wrapper scripts + src)
  local backup_dir = work_dir .. (is_windows and "\\backup" or "/backup")
  os.execute(
    (is_windows and "mkdir " or "mkdir -p ") .. backup_dir .. (is_windows and " >NUL 2>&1" or " >/dev/null 2>&1")
  )
  -- Copy wrappers (always files)
  local wrappers = {
    { from = join(install_root, "install", "almd.sh"), to = join(backup_dir, "almd.sh") },
    { from = join(install_root, "install", "almd.bat"), to = join(backup_dir, "almd.bat") },
    { from = join(install_root, "install", "almd.ps1"), to = join(backup_dir, "almd.ps1") },
  }
  for _, w in ipairs(wrappers) do
    if path_exists(w.from) then
      if is_windows then
        shell(cp .. ' "' .. w.from .. '" "' .. w.to .. '"' .. (is_windows and " /Y /Q >NUL 2>&1" or " >/dev/null 2>&1"))
      else
        shell(cp .. ' "' .. w.from .. '" "' .. w.to .. '"' .. (is_windows and "" or " >/dev/null 2>&1"))
      end
    end
  end
  -- Copy src directory
  local src_dir = join(install_root, "src")
  if path_exists(src_dir) then
    if is_windows then
      shell(
        xcopy
          .. ' "'
          .. src_dir
          .. '" "'
          .. join(backup_dir, "src")
          .. '"'
          .. (is_windows and " /E /I /Y /Q >NUL 2>&1" or " >/dev/null 2>&1")
      )
    else
      shell(
        xcopy .. ' "' .. src_dir .. '" "' .. join(backup_dir, "src") .. '"' .. (is_windows and "" or " >/dev/null 2>&1")
      )
    end
  end

  -- Windows: Check if files are locked (in use) before proceeding
  if is_windows then
    local function is_file_locked(path)
      local lock_handle = io.open(path, "r+")
      if lock_handle then
        lock_handle:close()
        return false
      end
      return true
    end
    local files_to_check = {
      join(install_root, "src", "main.lua"),
      join(install_root, "install", "almd.sh"),
      join(install_root, "install", "almd.bat"),
      join(install_root, "install", "almd.ps1"),
    }
    local function stage_update_for_next_run(staging_dir, extracted_dir)
      -- Remove any existing staged update
      if path_exists(staging_dir) then
        if is_windows then
          shell('rmdir /s /q "' .. staging_dir .. '" >NUL 2>&1')
        else
          shell('rm -rf "' .. staging_dir .. '" >/dev/null 2>&1')
        end
      end
      -- Copy extracted_dir to staging_dir
      if is_windows then
        shell('xcopy "' .. extracted_dir .. '" "' .. staging_dir .. '" /E /I /Y /Q >NUL 2>&1')
      else
        shell('cp -r "' .. extracted_dir .. '" "' .. staging_dir .. '" >/dev/null 2>&1')
      end
      -- Write marker file
      local marker = io.open(join(install_root, "install", "update_pending"), "w")
      if marker then
        marker:write(os.date("%Y-%m-%dT%H:%M:%S"))
        marker:close()
      end
    end
    local locked_file = nil
    for _, file in ipairs(files_to_check) do
      if is_file_locked(file) then
        locked_file = file
        break
      end
    end
    if locked_file then
      local staging_dir = join(install_root, "install", "next")
      stage_update_for_next_run(staging_dir, final_dir)
      return false, "Update staged for next run."
    end
  end

  -- Step 6: Replace install tree with new version
  -- Remove old src and wrappers
  local rm = is_windows and "rmdir /s /q" or "rm -rf"
  shell(rm .. " " .. join(install_root, "src") .. (is_windows and " >NUL 2>&1" or " >/dev/null 2>&1"))
  shell(
    is_windows
        and (
          "del "
          .. join(install_root, "install", "almd.sh")
          .. " "
          .. join(install_root, "install", "almd.bat")
          .. " "
          .. join( -- luacheck: ignore 121
            install_root,
            "install",
            "almd.ps1"
          )
          .. " >NUL 2>&1"
        )
      or (
        "rm -f "
        .. join(install_root, "install", "almd.sh")
        .. " "
        .. join(install_root, "install", "almd.bat")
        .. " "
        .. join(install_root, "install", "almd.ps1")
        .. " >/dev/null 2>&1"
      )
  )
  -- Copy new src and wrappers
  local src_cmd, sh_cmd, bat_cmd, ps1_cmd
  if is_windows then
    src_cmd = xcopy .. ' "' .. final_dir .. '\\src" "' .. join(install_root, "src") .. '" /E /I /Y /Q >NUL 2>&1'
    sh_cmd = cp
      .. ' "'
      .. final_dir
      .. '\\install\\almd.sh" "'
      .. join(install_root, "install", "almd.sh")
      .. '" /Y /Q >NUL 2>&1'
    bat_cmd = cp
      .. ' "'
      .. final_dir
      .. '\\install\\almd.bat" "'
      .. join(install_root, "install", "almd.bat")
      .. '" /Y /Q >NUL 2>&1'
    ps1_cmd = cp
      .. ' "'
      .. final_dir
      .. '\\install\\almd.ps1" "'
      .. join(install_root, "install", "almd.ps1")
      .. '" /Y /Q >NUL 2>&1'
  else
    src_cmd = xcopy .. ' "' .. final_dir .. '/src" "' .. join(install_root, "src") .. '" >/dev/null 2>&1'
    sh_cmd = cp
      .. ' "'
      .. final_dir
      .. '/install/almd.sh" "'
      .. join(install_root, "install", "almd.sh")
      .. '" >/dev/null 2>&1'
    bat_cmd = cp
      .. ' "'
      .. final_dir
      .. '/install/almd.bat" "'
      .. join(install_root, "install", "almd.bat")
      .. '" >/dev/null 2>&1'
    ps1_cmd = cp
      .. ' "'
      .. final_dir
      .. '/install/almd.ps1" "'
      .. join(install_root, "install", "almd.ps1")
      .. '" >/dev/null 2>&1'
  end

  local ok_shell = shell(src_cmd) and shell(sh_cmd) and shell(bat_cmd) and shell(ps1_cmd)
  if not ok_shell then
    return false,
      "Failed to copy new files during update. Please check permissions and available disk space, and retry."
  end

  -- Step 7: Validate new install
  local ok_new = io.open(join(install_root, "src", "main.lua"), "r")
  if not ok_new then
    -- Rollback: restore from backup
    if is_windows then
      local src_restore = join(backup_dir, "src")
      if path_exists(src_restore) then
        shell(xcopy .. ' "' .. src_restore .. '" "' .. join(install_root, "src") .. '" /E /I /Y /Q >NUL 2>&1')
      end
      for _, w in ipairs(wrappers) do
        if path_exists(w.from) then
          shell(cp .. ' "' .. join(backup_dir, w.to:match("([^/\\]+)$")) .. '" "' .. w.to .. '" /Y /Q >NUL 2>&1')
        end
      end
    else
      local src_restore = join(backup_dir, "src")
      if path_exists(src_restore) then
        shell(xcopy .. ' "' .. src_restore .. '" "' .. join(install_root, "src") .. '" >/dev/null 2>&1')
      end
    end
    return false, "Update failed: new version not found, rolled back to previous version."
  else
    ok_new:close()
  end

  -- Step 8: Delete backup and temp work dir
  shell(rm .. " " .. backup_dir .. (is_windows and " >NUL 2>&1" or " >/dev/null 2>&1"))
  shell(rm .. " " .. work_dir .. (is_windows and " >NUL 2>&1" or " >/dev/null 2>&1"))
  return true, "Update staged for next run."
end

--- Prints usage/help information for the `self` command.
-- @param print_fn [function] Optional. Function to use for printing (default: print)
function M.help_info(print_fn)
  print_fn = print_fn or print
  print_fn("Usage: almd self uninstall")
  print_fn("Uninstalls the Almandine CLI and removes all associated files.")
end

return M
