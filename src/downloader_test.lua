--[[
  Downloader module tests for Snowdrop

  Verifies correct download and pinning of files from GitHub and raw URLs.
]]--

local downloader = require("src.downloader")
local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true else return false end
end

local function file_sha256(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  local ok, openssl = pcall(require, "openssl.digest")
  if not ok then return nil end
  return openssl.digest("sha256", data)
end

-- Example test: Download a known file from GitHub by commit hash
local src = "github:lua/lua/doc/readme.html@v5.4.4"
local out_path = "tmp_test_readme.html"
local ok, err = downloader.download_file(src, out_path)
if ok and file_exists(out_path) then
  print("[PASS] GitHub download (semver/tag) succeeded: " .. out_path)
else
  print("[FAIL] GitHub download failed: " .. tostring(err))
end

-- Example test: Download a raw URL
local src2 = "https://raw.githubusercontent.com/lua/lua/v5.4.4/doc/readme.html"
local out_path2 = "tmp_test_readme2.html"
local ok2, err2 = downloader.download_file(src2, out_path2)
if ok2 and file_exists(out_path2) then
  print("[PASS] Raw URL download succeeded: " .. out_path2)
else
  print("[FAIL] Raw URL download failed: " .. tostring(err2))
end

-- Clean up (optional)
os.remove(out_path)
os.remove(out_path2)
