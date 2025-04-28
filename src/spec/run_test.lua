--[[
  Run Command Test

  Tests for the run command module and CLI integration.
]]--

-- Ensure src/ is in the package.path for module resolution
local src_path = "src/?.lua"
if not string.find(package.path, src_path, 1, true) then
  package.path = src_path .. ";" .. package.path
end

local run_module = require("modules.run")
local manifest_loader = require("utils.manifest")

local function fake_manifest_loader(scripts)
  return {
    safe_load_project_manifest = function()
      return { scripts = scripts }, nil
    end
  }
end

local function test_run_script_success()
  local scripts = { hello = "echo hello world" }
  local loader = fake_manifest_loader(scripts)
  local ok, err = run_module.run_script("hello", loader)
  assert(ok, "Expected script to run successfully")
end

local function test_run_script_missing()
  local scripts = { hello = "echo hello world" }
  local loader = fake_manifest_loader(scripts)
  local ok, err = run_module.run_script("notfound", loader)
  assert(not ok, "Expected script to fail for missing script")
  assert(err:match("not found"), "Expected error message for missing script")
end

local function test_is_reserved_command()
  assert(run_module.is_reserved_command("init"), "init should be reserved")
  assert(not run_module.is_reserved_command("hello"), "hello should not be reserved")
end

local function test_get_unambiguous_script()
  local scripts = { foo = "echo foo", bar = "echo bar" }
  local loader = fake_manifest_loader(scripts)
  assert(run_module.get_unambiguous_script("foo", loader) == "foo", "Should resolve foo")
  assert(run_module.get_unambiguous_script("baz", loader) == nil, "baz should not resolve")
end

local function run_all()
  test_run_script_success()
  test_run_script_missing()
  test_is_reserved_command()
  test_get_unambiguous_script()
  print("run_test.lua: All tests passed.")
end

run_all()
