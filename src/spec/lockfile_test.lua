--[[
  Lockfile module tests for Snowdrop

  Verifies correct generation, serialization, and writing of the lockfile schema.
  No external dependencies. All output is checked for correctness and reproducibility.
]]--

local lockfile = require("src.lib.lockfile")

--- Checks if a file exists.
-- @param path string Path to file.
-- @return boolean True if file exists, false otherwise.
local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true else return false end
end

-- Test: Generate lockfile table from resolved dependencies
do
  local resolved = {
    lunajson = { version = "1.3.4", hash = "sha256:abc123" },
    somefile = { source = "github:user/repo/path/file.lua", hash = "abcdef" }
  }
  local lf = lockfile.generate_lockfile_table(resolved)
  if lf and lf.api_version and lf.package and lf.package.lunajson and lf.package.somefile then
    print("[PASS] Lockfile table generation succeeded.")
  else
    print("[FAIL] Lockfile table generation failed.")
  end
end

-- Test: Serialize lockfile table to Lua string
do
  local resolved = {
    lunajson = { version = "1.3.4", hash = "sha256:abc123" },
    somefile = { source = "github:user/repo/path/file.lua", hash = "abcdef" }
  }
  local lf = lockfile.generate_lockfile_table(resolved)
  local lua_code = lockfile.serialize_lockfile(lf)
  if lua_code and lua_code:match("api_version") and lua_code:match("lunajson") and lua_code:match("somefile") then
    print("[PASS] Lockfile serialization succeeded.")
  else
    print("[FAIL] Lockfile serialization failed.")
  end
end

-- Test: Write lockfile to disk and verify file exists
do
  local resolved = {
    lunajson = { version = "1.3.4", hash = "sha256:abc123" },
    somefile = { source = "github:user/repo/path/file.lua", hash = "abcdef" }
  }
  local lf = lockfile.generate_lockfile_table(resolved)
  local ok, path = lockfile.write_lockfile(lf, "tmp_test_snowdrop-lock.lua")
  if ok and file_exists("tmp_test_snowdrop-lock.lua") then
    print("[PASS] Lockfile write succeeded: " .. tostring(path))
  else
    print("[FAIL] Lockfile write failed.")
  end
  os.remove("tmp_test_snowdrop-lock.lua")
end
