--[[
  Downloader Utility

  Provides functions to download files for dependencies.
]]--

local downloader = {}

--- Download a file from a URL to a local path.
-- @param url string URL to download from.
-- @param out_path string Local file path to save to.
-- @return boolean, string|nil True if success, or false and error message.
function downloader.download(url, out_path)
  local http = require("socket.http")
  local ltn12 = require("ltn12")
  local file, err = io.open(out_path, "wb")
  if not file then return false, err end
  local ok, http_err = http.request{
    url = url,
    sink = ltn12.sink.file(file)
  }
  if not ok then return false, http_err end
  return true
end

return downloader
