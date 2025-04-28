--[[
  Add Module Unit Test

  Tests the add_dependency function in src/modules/add.lua:
  - Verifies that a dependency is added to the manifest
  - Verifies that downloader is called with correct arguments
  - Stubs manifest loader/saver and downloader
  - Does not touch real files or network

  Usage: lua src/spec/add_module_test.lua
]]--

-- Ensure src/ is in package.path for require
local src_path = "src/?.lua"
if not string.find(package.path, src_path, 1, true) then
  package.path = src_path .. ";" .. package.path
end

local add_mod = require("modules.add")

local function make_fake_manifest()
  return {
    name = "test-project",
    type = "application",
    version = "0.0.1",
    license = "MIT",
    description = "Test manifest",
    scripts = {},
    dependencies = {}
  }
end

local function test_add_simple()
  local manifest = make_fake_manifest()
  local saved_manifest = nil
  local save_called = false
  local function load_manifest()
    return manifest, nil
  end
  local function save_manifest(m)
    saved_manifest = m
    save_called = true
    return true, nil
  end
  local ensure_lib_dir_called = false
  local function ensure_lib_dir()
    ensure_lib_dir_called = true
  end
  local downloader_called = false
  local downloader_args = {}
  local downloader = {
    download = function(url, out_path)
      downloader_called = true
      downloader_args.url = url
      downloader_args.out_path = out_path
      return true, nil
    end
  }
  local dep_name = "foo"
  local dep_url = "https://example.com/foo.lua"
  add_mod.add_dependency(dep_name, dep_url, load_manifest, save_manifest, ensure_lib_dir, downloader)

  assert(save_called, "save_manifest was not called")
  assert(saved_manifest.dependencies[dep_name] == dep_url, "Dependency not added to manifest")
  assert(ensure_lib_dir_called, "ensure_lib_dir was not called")
  assert(downloader_called, "downloader.download was not called")
  assert(downloader_args.url == dep_url, "downloader.download url arg incorrect")
  assert(downloader_args.out_path == "src/lib/foo.lua", "downloader.download out_path arg incorrect")
  print("[PASS] test_add_simple")
end

local function test_add_table_source()
  local manifest = make_fake_manifest()
  local saved_manifest = nil
  local function load_manifest()
    return manifest, nil
  end
  local function save_manifest(m)
    saved_manifest = m
    return true, nil
  end
  local ensure_lib_dir = function() end
  local downloader_args = {}
  local downloader = {
    download = function(url, out_path)
      downloader_args.url = url
      downloader_args.out_path = out_path
      return true, nil
    end
  }
  local dep_name = "bar"
  local dep_source = { url = "https://example.com/bar.lua", path = "custom/bar.lua" }
  add_mod.add_dependency(dep_name, dep_source, load_manifest, save_manifest, ensure_lib_dir, downloader)
  assert(saved_manifest.dependencies[dep_name] == dep_source, "Dependency (table) not added to manifest")
  assert(downloader_args.url == dep_source.url, "downloader.download url arg incorrect for table source")
  assert(downloader_args.out_path == dep_source.path, "downloader.download out_path arg incorrect for table source")
  print("[PASS] test_add_table_source")
end

local function test_add_no_dep()
  local manifest = make_fake_manifest()
  local function load_manifest() return manifest, nil end
  local save_manifest = function() error("Should not be called") end
  local ensure_lib_dir = function() end
  local downloader = { download = function() error("Should not be called") end }
  add_mod.add_dependency(nil, nil, load_manifest, save_manifest, ensure_lib_dir, downloader)
  print("[PASS] test_add_no_dep (no error)")
end

local function run_all()
  test_add_simple()
  test_add_table_source()
  test_add_no_dep()
  print("[TEST RESULT] All add_module tests passed.")
end

run_all()
