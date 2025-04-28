--[[
  Remove Command Test Suite

  Tests the remove functionality for the Almandine package manager.
  Ensures dependencies are properly removed from project.lua and corresponding files are deleted.
  This test does not require external dependencies and is compatible with Lua 5.1+.
]]--

local src_path = "src/?.lua"
local lib_path = "src/lib/?.lua"
if not string.find(package.path, src_path, 1, true) then
  package.path = src_path .. ";" .. package.path
end
if not string.find(package.path, lib_path, 1, true) then
  package.path = lib_path .. ";" .. package.path
end

local main = require("main")
local manifest_loader = require("utils.manifest")

local TEST_DEP_NAME = "testdep"
local TEST_DEP_PATH = "src/lib/testdep.lua"
local MANIFEST_FILE = "project.lua"

local function write_manifest(deps)
  local file = assert(io.open(MANIFEST_FILE, "w"))
  file:write("return {\n")
  file:write("  name = \"testproj\",\n")
  file:write("  type = \"application\",\n")
  file:write("  version = \"0.1.0\",\n")
  file:write("  license = \"MIT\",\n")
  file:write("  description = \"Test manifest\",\n")
  file:write("  scripts = {},\n")
  file:write("  dependencies = {\n")
  for k, v in pairs(deps) do
    file:write(string.format("    [%q] = %q,\n", k, v))
  end
  file:write("  }\n")
  file:write("}\n")
  file:close()
end

local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

local function cleanup()
  os.remove(MANIFEST_FILE)
  os.remove(TEST_DEP_PATH)
end

local function test_remove_existing()
  print("[TEST] Removing existing dependency...")
  write_manifest({ [TEST_DEP_NAME] = "dummy_source" })
  -- Create dummy dep file
  os.execute("mkdir src/lib >nul 2>&1")
  local f = assert(io.open(TEST_DEP_PATH, "w"))
  f:write("dummy content")
  f:close()
  assert(file_exists(TEST_DEP_PATH), "Dependency file should exist before removal")
  local function save_manifest(m)
    -- Fill in required manifest fields for compatibility
    m.name = "testproj"
    m.type = "application"
    m.version = "0.1.0"
    m.license = "MIT"
    m.description = "Test manifest"
    m.scripts = m.scripts or {}
    local deps = m.dependencies or {}
    write_manifest(deps)
    return true, nil
  end
  main.remove_dependency(TEST_DEP_NAME, manifest_loader.safe_load_project_manifest, save_manifest)
  local manifest, err = manifest_loader.safe_load_project_manifest()
  if not manifest then
    print("[FAIL] Could not load manifest after removal: "..tostring(err))
    return
  end
  if manifest.dependencies and not manifest.dependencies[TEST_DEP_NAME] and not file_exists(TEST_DEP_PATH) then
    print("[PASS] Dependency removed and file deleted.")
  else
    print("[FAIL] Dependency/file not removed correctly.")
    if manifest.dependencies and manifest.dependencies[TEST_DEP_NAME] then
      print("[DEBUG] Dependency still in manifest.")
    end
    if file_exists(TEST_DEP_PATH) then
      print("[DEBUG] Dependency file still exists.")
    end
  end
end

local function test_remove_nonexistent()
  print("[TEST] Removing nonexistent dependency...")
  write_manifest({})
  main.remove_dependency("doesnotexist", manifest_loader.safe_load_project_manifest, function(m)
    return write_manifest(m.dependencies or {})
  end)
  print("[PASS] No error on removing nonexistent dependency (check output above for warning).")
end

local function run_tests()
  cleanup()
  test_remove_existing()
  test_remove_nonexistent()
  cleanup()
end

run_tests()
