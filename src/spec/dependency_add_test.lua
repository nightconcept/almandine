--[[
  Automated test for Task 4.2: Add, download, and verify real dependencies
  - Adds a set of real dependencies to project.lua
  - Invokes the install logic
  - Verifies that files are downloaded and hashes match the manifest
  - Attempts removal (skipped if not implemented)

  This test is designed to be run in a clean project root and will overwrite project.lua.
  It uses only the allowed folder structure and no external dependencies.

  Usage: lua src/spec/dependency_add_test.lua
]]--

-- Ensure src/ is in package.path for require
local src_path = "src/?.lua"
if not string.find(package.path, src_path, 1, true) then
  package.path = src_path .. ";" .. package.path
end

local downloader = require("lib.downloader")

-- Minimal pure Lua SHA-1 implementation for test purposes
-- (Based on public domain code, see: https://github.com/kikito/sha1.lua)
local function be32(bytes, i)
  local b1, b2, b3, b4 = string.byte(bytes, i, i+3)
  return bit.lshift(b1,24) + bit.lshift(b2,16) + bit.lshift(b3,8) + b4
end

local function sha1_bin(msg)
  local bit = bit32 or (package.loaded["bit"] and require("bit")) or _G.bit
  if not bit then error("bit32 or LuaBitOp required for SHA-1") end
  local band, bor, bxor, bnot, lshift, rshift = bit.band, bit.bor, bit.bxor, bit.bnot, bit.lshift, bit.rshift
  local function leftrotate(a, b) return bor(lshift(a, b), rshift(a, 32-b)) end
  local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
  local ml = #msg * 8
  msg = msg .. string.char(0x80)
  local pad_len = (56 - (#msg % 64)) % 64
  msg = msg .. string.rep("\0", pad_len)
  msg = msg .. string.char(
    band(rshift(ml,56),0xff), band(rshift(ml,48),0xff), band(rshift(ml,40),0xff), band(rshift(ml,32),0xff),
    band(rshift(ml,24),0xff), band(rshift(ml,16),0xff), band(rshift(ml,8),0xff), band(ml,0xff))
  for i=1, #msg, 64 do
    local w = {}
    for j=0,15 do
      w[j+1] = be32(msg, i + j*4)
    end
    for j=17,80 do
      w[j] = leftrotate(bxor(bxor(bxor(w[j-3], w[j-8]), w[j-14]), w[j-16]), 1)
    end
    local a, b, c, d, e = h0, h1, h2, h3, h4
    for j=1,80 do
      local f, k
      if j<=20 then f = bor(band(b,c), band(bnot(b),d)); k=0x5A827999
      elseif j<=40 then f = bxor(b,c,d); k=0x6ED9EBA1
      elseif j<=60 then f = bor(bor(band(b,c), band(b,d)), band(c,d)); k=0x8F1BBCDC
      else f = bxor(b,c,d); k=0xCA62C1D6 end
      local temp = (leftrotate(a,5) + f + e + k + w[j]) % 0x100000000
      e, d, c, b, a = d, c, leftrotate(b,30), a, temp
    end
    h0 = (h0 + a) % 0x100000000
    h1 = (h1 + b) % 0x100000000
    h2 = (h2 + c) % 0x100000000
    h3 = (h3 + d) % 0x100000000
    h4 = (h4 + e) % 0x100000000
  end
  return string.format("%08x%08x%08x%08x%08x", h0, h1, h2, h3, h4)
end

local function sha1_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  local ok, hash = pcall(sha1_bin, data)
  if not ok then return nil end
  return hash
end

--- Checks if a file exists.
-- @param path string Path to file.
-- @return boolean True if file exists, false otherwise.
local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true else return false end
end

-- Dependency array (from user)
local dependencies = {
  {
    url = "https://raw.githubusercontent.com/Oval-Tutu/shove/main/shove.lua",
    path = "src/spec/shove.lua"
  },
  {
    url = "https://raw.githubusercontent.com/Oval-Tutu/shove/main/shove-profiler.lua",
    path = "src/spec/shove-profiler.lua"
  },
  {
    url = "https://raw.githubusercontent.com/mdqinc/SDL_GameControllerDB/master/gamecontrollerdb.txt",
    path = "src/spec/gamecontrollerdb.txt"
  },
}

-- Manifest of expected hashes
local manifest = {
  ["src/spec/shove.lua"] = "56a599899892782b72f71a61f9049a38d8b772fd",
  ["src/spec/shove-profiler.lua"] = "e4101241c85525a7ffcbcc1b9987a1d73ce2dec1",
  ["src/spec/gamecontrollerdb.txt"] = "19c0efbb97aac61782df8ce9de52230cd4fb7a2e",
}

-- Set up mapping for test output paths
_G.dependency_add_test_paths = {}
for _, dep in ipairs(dependencies) do
  local key = dep.path:match("([^/]+)$"):gsub("%.lua$","")
  _G.dependency_add_test_paths[key] = dep.path
end

-- 1. Overwrite project.lua with these dependencies
local function write_manifest()
  local f = assert(io.open("project.lua", "w"))
  f:write("return {\n")
  f:write("  name = \"dep-test\",\n")
  f:write("  type = \"application\",\n")
  f:write("  lua = \"\\u003e=5.1\",\n")
  f:write("  version = \"0.1.0\",\n")
  f:write("  license = \"MIT\",\n")
  f:write("  description = \"Dependency add/download test\",\n")
  f:write("  scripts = {},\n")
  f:write("  dependencies = {\n")
  for _, dep in ipairs(dependencies) do
    -- Use file name as key, url as value
    local key = dep.path:match("([^/]+)$"):gsub("%.lua$","")
    f:write(string.format("    [%q] = \"%s\",\n", key, dep.url))
  end
  f:write("  }\n}\n")
  f:close()
end

-- 2. Install dependencies (simulate CLI: call install_dependency)
local function install_all()
  -- Use the same logic as main.lua's install_dependency
  local main = require("main")
  for _, dep in ipairs(dependencies) do
    local key = dep.path:match("([^/]+)$"):gsub("%.lua$","")
    print("Installing "..key.."...")
    main.install_dependency(key, dep.url)
  end
end

-- 3. Verify files exist and (optionally) hashes match
local function verify_files()
  local all_ok = true
  for _, dep in ipairs(dependencies) do
    if file_exists(dep.path) then
      print("[PASS] File exists: "..dep.path)
      local hash = sha1_file(dep.path)
      if hash == manifest[dep.path] then
        print("[PASS] Hash matches for "..dep.path)
      else
        print("[FAIL] Hash mismatch for "..dep.path.." (got "..tostring(hash)..")")
        all_ok = false
      end
    else
      print("[FAIL] File missing: "..dep.path)
      all_ok = false
    end
  end
  return all_ok
end

-- 4. Attempt removal (if implemented)
local function try_remove()
  local ok, main = pcall(require, "main")
  if not ok or not main.remove_dependency then
    print("[SKIP] Remove not implemented.")
    return
  end
  for _, dep in ipairs(dependencies) do
    local key = dep.path:match("([^/]+)$"):gsub("%.lua$","")
    print("Removing "..key.."...")
    main.remove_dependency(key)
    if not file_exists(dep.path) then
      print("[PASS] Removed: "..dep.path)
    else
      print("[FAIL] File still exists after remove: "..dep.path)
    end
  end
end

-- Run test
print("[TEST] Writing manifest...")
io.flush()
write_manifest()
print("[TEST] Installing dependencies...")
io.flush()
install_all()
print("[TEST] Verifying files...")
io.flush()
local ok = verify_files()
print("[TEST] Attempting removal...")
io.flush()
try_remove()
if ok then
  print("[TEST RESULT] Dependency add/download test PASSED (files present; hash check stubbed)")
else
  print("[TEST RESULT] Dependency add/download test FAILED (missing files)")
end
io.flush()
print("[TEST END]")
io.flush()
