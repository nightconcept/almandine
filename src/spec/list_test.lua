--[[
  List Command Test Suite

  Tests the list functionality for the Almandine package manager.
  Ensures dependencies are properly listed from almd-lock.lua if present, or from project.lua otherwise.
  Compatible with Lua 5.1+ and does not require external dependencies.
]]--

local src_path = "src/?.lua"
local lib_path = "src/lib/?.lua"
if not string.find(package.path, src_path, 1, true) then
  package.path = src_path .. ";" .. package.path
end
if not string.find(package.path, lib_path, 1, true) then
  package.path = lib_path .. ";" .. package.path
end

local list_module = require("modules.list")
local manifest_loader = require("utils.manifest")

local MANIFEST_FILE = "project.lua"
local LOCKFILE = "almd-lock.lua"

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
    if type(v) == "string" then
      file:write(string.format("    [%q] = %q,\n", k, v))
    elseif type(v) == "table" then
      file:write(string.format("    [%q] = { version = %q },\n", k, v.version or ""))
    end
  end
  file:write("  }\n")
  file:write("}\n")
  file:close()
end

local function write_lockfile(pkgs)
  local file = assert(io.open(LOCKFILE, "w"))
  file:write("return {\n  api_version = \"1\",\n  package = {\n")
  for k, v in pairs(pkgs) do
    file:write(string.format("    [%q] = { version = %q, hash = %q },\n", k, v.version or "", v.hash or ""))
  end
  file:write("  }\n}\n")
  file:close()
end

local function cleanup()
  os.remove(MANIFEST_FILE)
  os.remove(LOCKFILE)
end

local function capture_print(func)
  local output = {}
  local _print = print
  print = function(...) local t = {}
    for i=1,select('#', ...) do t[#t+1] = tostring(select(i, ...)) end
    output[#output+1] = table.concat(t, " ")
  end
  func()
  print = _print
  return table.concat(output, "\n")
end

local function test_list_with_lockfile()
  print("[TEST] List with lockfile...")
  write_manifest({ foo = "src", bar = { version = "1.2.3" } })
  write_lockfile({ foo = { version = "0.9.0", hash = "abc123" }, bar = { version = "1.2.3", hash = "def456" } })
  local out = capture_print(function()
    list_module.list_dependencies(manifest_loader.safe_load_project_manifest, LOCKFILE)
  end)
  assert(out:find("foo") and out:find("0.9.0"), "foo@0.9.0 should be listed")
  assert(out:find("bar") and out:find("1.2.3"), "bar@1.2.3 should be listed")
  print("[PASS] Lockfile listing correct.")
end

local function test_list_fallback_to_manifest()
  print("[TEST] List fallback to manifest...")
  write_manifest({ foo = "src", bar = { version = "1.2.3" } })
  os.remove(LOCKFILE)
  local out = capture_print(function()
    list_module.list_dependencies(manifest_loader.safe_load_project_manifest, LOCKFILE)
  end)
  assert(out:find("foo") and out:find("src"), "foo@src should be listed")
  assert(out:find("bar") and out:find("1.2.3"), "bar@1.2.3 should be listed")
  print("[PASS] Manifest fallback listing correct.")
end

local function test_list_no_deps()
  print("[TEST] List with no dependencies...")
  write_manifest({})
  os.remove(LOCKFILE)
  local out = capture_print(function()
    list_module.list_dependencies(manifest_loader.safe_load_project_manifest, LOCKFILE)
  end)
  assert(out:find("No dependencies found"), "Should report no dependencies")
  print("[PASS] No dependencies handled.")
end

local function run_tests()
  cleanup()
  test_list_with_lockfile()
  test_list_fallback_to_manifest()
  test_list_no_deps()
  cleanup()
end

run_tests()
