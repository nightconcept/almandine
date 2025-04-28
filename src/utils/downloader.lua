--[[
  Downloader Utility

  Provides functions to download files for dependencies using system tools (wget or curl).
  No external Lua dependencies required. Cross-platform.
]]--

--- Downloader utility module.
-- Provides file download functionality using wget or curl.
-- @module downloader

local downloader = {}

--- Check if a given command exists in the system PATH.
-- @param cmd string Command name (e.g., "wget").
-- @return boolean True if command exists, false otherwise.
local function has_command(cmd)
  local check = package.config:sub(1,1) == "\\" and ("where " .. cmd .. ">NUL 2>NUL") or ("command -v " .. cmd .. " >/dev/null 2>&1")
  local ok = os.execute(check)
  return ok == true or ok == 0
end

--- Download a file from a URL to a local path using wget or curl.
-- @param url string URL to download from.
-- @param out_path string Local file path to save to.
-- @return boolean, string|nil True if success, or false and error message.
function downloader.download(url, out_path)
  if has_command("wget") then
    local cmd = string.format('wget -O "%s" "%s"', out_path, url)
    local ok = os.execute(cmd)
    if ok == 0 or ok == true then
      return true
    else
      return false, "wget failed with exit code " .. tostring(ok)
    end
  elseif has_command("curl") then
    local cmd = string.format('curl -fSL -o "%s" "%s"', out_path, url)
    local ok = os.execute(cmd)
    if ok == 0 or ok == true then
      return true
    else
      return false, "curl failed with exit code " .. tostring(ok)
    end
  else
    return false, "Neither wget nor curl is available on this system. Please install one to enable downloads."
  end
end

return downloader
