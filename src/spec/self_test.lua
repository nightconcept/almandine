--[[
  Test for self.uninstall_self()

  This test creates dummy wrapper scripts and a dummy src/ directory, invokes uninstall_self(), and asserts that all targets are removed.
]]--

local busted = require("busted")

-- Add src/ to package.path for module resolution
local src_path = "src/?.lua"
if not string.find(package.path, src_path, 1, true) then
  package.path = src_path .. ";" .. package.path
end

local self_module = 
  require("modules.self")

local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

local function dir_exists(path)
  -- POSIX only: use os.execute('test -d path')
  local cmd = string.format('test -d %q', path)
  local ok = os.execute(cmd)
  return ok == 0 or ok == true
end

local function make_dummy_file(path)
  local f = io.open(path, "w")
  f:write("dummy")
  f:close()
end

local function make_dummy_dir(path)
  os.execute('mkdir -p ' .. path)
  make_dummy_file(path .. "/dummy.lua")
end

local function cleanup()
  os.remove("install/almd.sh")
  os.remove("install/almd.bat")
  os.remove("install/almd.ps1")
  os.execute('rm -rf src')
end

-- Test setup
cleanup()
os.execute('mkdir -p install')
make_dummy_file("install/almd.sh")
make_dummy_file("install/almd.bat")
make_dummy_file("install/almd.ps1")
make_dummy_dir("src")

-- Run uninstall_self
local ok, err = self_module.uninstall_self()

-- Assertions
assert(ok, "uninstall_self() should succeed: " .. (err or "no error"))
assert(not file_exists("install/almd.sh"), "almd.sh should be removed")
assert(not file_exists("install/almd.bat"), "almd.bat should be removed")
assert(not file_exists("install/almd.ps1"), "almd.ps1 should be removed")
assert(not dir_exists("src"), "src directory should be removed")

print("self_uninstall_test.lua: PASS")

-- Cleanup after test
cleanup()
