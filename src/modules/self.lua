--[[
  Self Command Module

  Implementation for self-uninstall and future self-update features.
  This module provides removal of CLI wrapper scripts and the CLI Lua folder.
]]
--

--- Recursively delete a directory and its contents (cross-platform: POSIX and Windows)
-- @param path [string] Directory path to delete
-- @return [boolean, string?] True if successful, or false and error message
local function rmdir_recursive(path)
  local is_windows = package.config:sub(1, 1) == "\\"
  local cmd
  if is_windows then
    -- Windows: use rmdir /s /q
    cmd = string.format('rmdir /s /q "%s"', path)
  else
    -- POSIX: use rm -rf
    cmd = string.format("rm -rf %q", path)
  end
  local ok = os.execute(cmd)
  if ok == 0 or ok == true then
    return true
  else
    return false, "Failed to remove directory: " .. path
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

--- Atomically self-update the CLI from the latest GitHub release.
-- Downloads, extracts, backs up, and atomically replaces the install tree.
-- Only deletes backup if new version is fully extracted and ready.
-- @return [boolean, string?] True if successful, or false and error message
local function self_update()
  local is_windows = package.config:sub(1, 1) == "\\"
  local tmp_dir = is_windows and os.getenv("TEMP") or "/tmp"
  local uuid = tostring(os.time()) .. tostring(math.random(10000, 99999))
  local work_dir = tmp_dir .. (is_windows and "\\almd_update_" or "/almd_update_") .. uuid
  local repo = "nightconcept/almandine"
  local tag_url = "https://api.github.com/repos/" .. repo .. "/tags?per_page=1"
  local zip_url, tag

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

  -- Step 1: Fetch latest tag
  local tag_file = work_dir .. (is_windows and "\\tag.json" or "/tag.json")
  os.execute((is_windows and "mkdir " or "mkdir -p ") .. work_dir)
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
  zip_url = "https://github.com/" .. repo .. "/archive/refs/tags/" .. tag .. ".zip"

  -- Step 2: Download zip
  local zip_path = work_dir .. (is_windows and "\\almd.zip" or "/almd.zip")
  ok, err = download(zip_url, zip_path)
  if not ok then
    return false, "Failed to download release zip: " .. (err or "unknown error")
  end

  -- Step 3: Extract zip
  local extract_dir = work_dir .. (is_windows and "\\extract" or "/extract")
  os.execute((is_windows and "mkdir " or "mkdir -p ") .. extract_dir)
  local unzip_cmd = is_windows
      and ("powershell -Command \"Add-Type -A 'System.IO.Compression.FileSystem'; " .. "[IO.Compression.ZipFile]::ExtractToDirectory('" .. zip_path .. "', '" .. extract_dir .. "')\"") -- luacheck: ignore 121
    or ("unzip -q -o '" .. zip_path .. "' -d '" .. extract_dir .. "'")
  if not shell(unzip_cmd) then
    return false, "Failed to extract release zip"
  end

  -- Step 4: Find extracted folder
  local extracted = extract_dir .. (is_windows and ("\\almandine-" .. tag) or ("/almandine-" .. tag))
  local extracted_v = extract_dir .. (is_windows and ("\\almandine-v" .. tag) or ("/almandine-v" .. tag))
  local f = io.open(extracted .. "/src/main.lua") or io.open(extracted_v .. "/src/main.lua")
  local final_dir = f and (f:close() and (io.open(extracted .. "/src/main.lua") and extracted or extracted_v)) or nil
  if not final_dir then
    return false, "Could not find extracted CLI source in zip"
  end

  -- Step 5: Backup current install tree (wrapper scripts + src)
  local backup_dir = work_dir .. (is_windows and "\\backup" or "/backup")
  os.execute((is_windows and "mkdir " or "mkdir -p ") .. backup_dir)
  local cp = is_windows and "xcopy /E /I /Q /Y" or "cp -r"
  -- Copy wrappers
  local wrappers = {
    { from = "install/almd.sh", to = backup_dir .. (is_windows and "\\almd.sh" or "/almd.sh") },
    { from = "install/almd.bat", to = backup_dir .. (is_windows and "\\almd.bat" or "/almd.bat") },
    { from = "install/almd.ps1", to = backup_dir .. (is_windows and "\\almd.ps1" or "/almd.ps1") },
  }
  for _, w in ipairs(wrappers) do
    shell(cp .. " " .. w.from .. " " .. w.to)
  end
  -- Copy src
  shell(cp .. " src " .. backup_dir .. (is_windows and "\\src" or "/src"))

  -- Step 6: Replace install tree with new version
  -- Remove old src and wrappers
  local rm = is_windows and "rmdir /s /q" or "rm -rf"
  shell(rm .. " src")
  shell(
    is_windows and "del install\\almd.sh install\\almd.bat install\\almd.ps1"
      or "rm -f install/almd.sh install/almd.bat install/almd.ps1"
  )
  -- Copy new src and wrappers
  local src_cmd = cp .. " " .. final_dir .. (is_windows and "\\src" or "/src") .. " src"
  local sh_cmd = cp
    .. " "
    .. final_dir
    .. (is_windows and "\\install\\almd.sh" or "/install/almd.sh")
    .. " install/almd.sh"
  local bat_cmd = cp
    .. " "
    .. final_dir
    .. (is_windows and "\\install\\almd.bat" or "/install/almd.bat")
    .. " install/almd.bat"
  local ps1_cmd = cp .. " " .. final_dir .. (is_windows and "\\install\\almd.ps1" or "/install/almd.ps1")
  ps1_cmd = ps1_cmd .. " install/almd.ps1"
  shell(src_cmd)
  shell(sh_cmd)
  shell(bat_cmd)
  shell(ps1_cmd)

  -- Step 7: Validate new install
  local ok_new = io.open("src/main.lua", "r")
  if not ok_new then
    -- Rollback: restore from backup
    shell(rm .. " src")
    shell(cp .. " " .. backup_dir .. (is_windows and "\\src" or "/src") .. " src")
    shell(cp .. " " .. backup_dir .. (is_windows and "\\almd.sh" or "/almd.sh") .. " install/almd.sh")
    shell(cp .. " " .. backup_dir .. (is_windows and "\\almd.bat" or "/almd.bat") .. " install/almd.bat")
    shell(cp .. " " .. backup_dir .. (is_windows and "\\almd.ps1" or "/almd.ps1") .. " install/almd.ps1")
    return false, "Update failed: new version not found, rolled back to previous version."
  end

  -- Step 8: Delete backup
  shell(rm .. " " .. backup_dir)
  shell(rm .. " " .. work_dir)
  return true
end

--- Prints usage/help information for the `self` command.
-- Usage: almd self uninstall
-- Uninstalls the Almandine CLI and removes all associated files.
local function help_info()
  print("Usage: almd self uninstall")
  print("Uninstalls the Almandine CLI and removes all associated files.")
end

return {
  uninstall_self = uninstall_self,
  self_update = self_update,
  help_info = help_info,
}
