--[[
  Downloader module tests for Snowdrop

  Verifies correct download and pinning of files from GitHub and raw URLs using only system curl/wget.
  No Lua dependencies required. Manual hash checking can be added if needed, but this test only verifies download success and file presence.
]]--

local downloader = require("src.lib.downloader")

--- Checks if a file exists.
-- @param path string Path to file.
-- @return boolean True if file exists, false otherwise.
local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true else return false end
end

-- Test 1: Download a known file from GitHub by tag (semver)
do
  local src = "github:lua/lua/README@v5.4.4"
  local out_path = "tmp_test_README.txt"
  local ok, err = downloader.download_file(src, out_path)
  if ok and file_exists(out_path) then
    print("[PASS] GitHub download (semver/tag) succeeded: " .. out_path)
  else
    print("[FAIL] GitHub download failed: " .. tostring(err))
  end
  os.remove(out_path)
end

-- Test 2: Download a raw URL
do
  local src = "https://raw.githubusercontent.com/lua/lua/v5.4.4/README"
  local out_path = "tmp_test_README2.txt"
  local ok, err = downloader.download_file(src, out_path)
  if ok and file_exists(out_path) then
    print("[PASS] Raw URL download succeeded: " .. out_path)
  else
    print("[FAIL] Raw URL download failed: " .. tostring(err))
  end
  os.remove(out_path)
end
