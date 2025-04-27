--[[
  Downloader module for Snowdrop Package Manager

  Provides functions to download single files from GitHub (with semver or commit hash pinning) or any raw URL.
  Used for dependency management and reproducible installs.
]]--

---
-- Downloader module
--
-- @module downloader
-- @usage local downloader = require('downloader')

local downloader = {}

local https_available, https = pcall(require, "ssl.https")
local http_available, http = pcall(require, "socket.http")
local ltn12 = require("ltn12")

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

  local ok, err = downloader._http_download(url, out_path)
  if not ok then
    return false, err
  end
  return true, nil
end

--- Internal HTTP(S) download helper.
-- @param url string URL to download.
-- @param out_path string Path to save file.
-- @return boolean, string True and nil on success; false and error message on failure.
function downloader._http_download(url, out_path)
  local file, err = io.open(out_path, "wb")
  if not file then return false, "Could not open file for writing: " .. tostring(err) end

  local resp_body = {}
  local result, status, resp_headers, status_line
  if https_available then
    result, status, resp_headers, status_line = https.request {
      url = url,
      sink = ltn12.sink.file(file)
    }
  elseif http_available then
    result, status, resp_headers, status_line = http.request {
      url = url,
      sink = ltn12.sink.file(file)
    }
  else
    file:close()
    return false, "LuaSocket or LuaSec not available (need socket.http or ssl.https)"
  end
  file:close()
  if status ~= 200 then
    return false, "HTTP error: " .. tostring(status) .. " (" .. tostring(status_line) .. ")"
  end
  return true, nil
end

return downloader
