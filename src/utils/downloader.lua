--[[
  Downloader Utility

  Provides functions to download files for dependencies using system tools (wget or curl).
  No external Lua dependencies required. Cross-platform.
]]
--

--- Downloader utility module.
-- Provides file download functionality using wget or curl.
-- @module downloader

local downloader = {}

-- Allow dependency injection for testability
local _os_execute = os.execute
local _package_config = package.config

local function set_test_env(os_execute, package_config)
  _os_execute = os_execute or os.execute
  _package_config = package_config or package.config
end

downloader._set_test_env = set_test_env

--- Check if a given command exists in the system PATH.
-- @param cmd string Command name (e.g., "wget").
-- @return boolean True if command exists, false otherwise.
local function has_command(cmd)
  local check = (_package_config:sub(1, 1) == "\\") and ("where " .. cmd .. ">NUL 2>NUL")
    or ("command -v " .. cmd .. " >/dev/null 2>&1")
  local ok = _os_execute(check)
  return ok == true or ok == 0
end

--- Download a file from a URL to a local path using wget or curl.
-- @param url string URL to download from.
-- @param out_path string Local file path to save to.
-- @param verbose boolean|nil If true, show full output from wget/curl. Defaults to false (quiet).
-- @return boolean, string|nil True if success, or false and error message.
function downloader.download(url, out_path, verbose)
  verbose = verbose or false
  local os_type = _package_config:sub(1, 1) == "\\" and "windows" or "unix"

  if has_command("wget") then
    local tool = "wget"
    local quiet_flag = ""
    local stderr_redirect = ""
    if not verbose then
      quiet_flag = "-q"
      stderr_redirect = (os_type == "unix") and " 2>/dev/null" or " 2>NUL"
    end
    -- Construct command: wget [-q] -O "<out_path>" "<url>" [stderr_redirect]
    local cmd = string.format('wget %s -O "%s" "%s"%s', quiet_flag, out_path, url, stderr_redirect)

    local ok = _os_execute(cmd)
    if ok == 0 or ok == true then
      return true
    else
      local exit_code = type(ok) == "number" and ok or "?"
      local error_msg =
        string.format("%s download failed (Exit Code: %s). Run with --verbose for details.", tool, exit_code)
      return false, error_msg
    end
  elseif has_command("curl") then
    local tool = "curl"
    local silent_flags = "-fL"
    if not verbose then
      -- -s (silent) -S (show error) -f (fail on server error) -L (follow redirects)
      silent_flags = "-fsSL"
    end
    -- Construct command: curl [-fsSL|-fL] -o "<out_path>" "<url>"
    -- No stderr redirect needed for curl as -sS handles it better
    local cmd = string.format('curl %s -o "%s" "%s"', silent_flags, out_path, url)
    local ok = _os_execute(cmd)
    if ok == 0 or ok == true then
      return true
    else
      local exit_code = type(ok) == "number" and ok or "?"
      local error_msg =
        string.format("%s download failed (Exit Code: %s). Run with --verbose for details.", tool, exit_code)
      return false, error_msg
    end
  else
    return false, "Neither wget nor curl is available on this system. Please install one to enable downloads."
  end
end

return downloader
