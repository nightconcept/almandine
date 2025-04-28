--[[
  Downloader module for Almandine Package Manager

  Provides functions to download single files from GitHub (with semver or commit hash pinning) or any raw URL.
  Used for dependency management and reproducible installs.
  Pure Lua 5.1, no dependencies. Uses curl or wget via os.execute/io.popen.
]]--

---
-- Downloader module
-- @module downloader
-- @usage local downloader = require('downloader')

local downloader = {}

--- Downloads a file from a GitHub repo or a raw URL, supporting pinning by semver or commit hash.
-- @param source string GitHub dependency string (github:user/repo/path/file.lua@abcdef) or raw URL.
-- @param out_path string Path to save the downloaded file.
-- @return boolean, string True and nil on success; false and error message on failure.
function downloader.download_file(source, out_path)
  assert(type(source) == "string", "source must be a string")
  assert(type(out_path) == "string", "out_path must be a string")

  local url = nil
  if source:match("^github:") then
    -- Parse github:user/repo/path/file.lua@version_or_hash
    local user, repo, path, ref = source:match("^github:([^/]+)/([^/]+)/(.+)%@([%w%._%-]+)$")
    if not (user and repo and path and ref) then
      return false, "Malformed GitHub source string: " .. source
    end
    url = string.format(
      "https://raw.githubusercontent.com/%s/%s/%s/%s",
      user, repo, ref, path
    )
  elseif source:match("^https?://") then
    url = source
  else
    return false, "Unsupported source format: " .. source
  end

  return downloader._shell_download(url, out_path)
end

--- Internal download helper using curl or wget (no Lua dependencies).
-- @param url string URL to download.
-- @param out_path string Path to save file.
-- @return boolean, string True and nil on success; false and error message on failure.
function downloader._shell_download(url, out_path)
  -- Prefer curl, fallback to wget
  local cmd = string.format('curl -fsSL "%s" -o "%s"', url, out_path)
  local ok = os.execute(cmd)
  if ok == 0 then
    return true, nil
  else
    -- Try wget if curl failed
    cmd = string.format('wget -qO "%s" "%s"', out_path, url)
    ok = os.execute(cmd)
    if ok == 0 then
      return true, nil
    end
  end
  return false, "Failed to download file. Ensure curl or wget is installed."
end

return downloader
