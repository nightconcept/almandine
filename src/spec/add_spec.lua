--[[
  Add Module Specification

  Busted test suite for add_dependency in src/modules/add.lua.
  - Verifies dependency addition, manifest update, downloader call, and name inference.
  - Uses only stubs/mocks and does not touch real files or network.
]]--

-- luacheck: globals describe it assert

--- Add module specification for Busted.
-- @module add_spec

describe("add_module.add_dependency", function()
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

  it("adds a simple dependency", function()
    local manifest = make_fake_manifest()
    local saved_manifest, save_called
    local function load_manifest() return manifest, nil end
    local function save_manifest(m) saved_manifest = m; save_called = true; return true, nil end
    local ensure_lib_dir_called = false
    local function ensure_lib_dir() ensure_lib_dir_called = true end
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
    assert.is_true(save_called)
    assert.are.equal(saved_manifest.dependencies[dep_name], dep_url)
    assert.is_true(ensure_lib_dir_called)
    assert.is_true(downloader_called)
    assert.are.equal(downloader_args.url, dep_url)
    assert.are.equal(downloader_args.out_path, "src/lib/foo.lua")
  end)

  it("adds a dependency from a table source", function()
    local manifest = make_fake_manifest()
    local saved_manifest
    local function load_manifest() return manifest, nil end
    local function save_manifest(m) saved_manifest = m; return true, nil end
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
    assert.are.same(saved_manifest.dependencies[dep_name], dep_source)
    assert.are.equal(downloader_args.url, dep_source.url)
    assert.are.equal(downloader_args.out_path, dep_source.path)
  end)

  it("does not fail when no dependency is given", function()
    local manifest = make_fake_manifest()
    local function load_manifest() return manifest, nil end
    local save_manifest = function() error("Should not be called") end
    local ensure_lib_dir = function() end
    local downloader = { download = function() return true, nil end }
    assert.has_no.errors(function()
      add_mod.add_dependency(nil, nil, load_manifest, save_manifest, ensure_lib_dir, downloader)
    end)
  end)

  it("infers name from URL if not provided", function()
    local manifest = make_fake_manifest()
    local saved_manifest, save_called
    local function load_manifest() return manifest, nil end
    local function save_manifest(m) saved_manifest = m; save_called = true; return true, nil end
    local ensure_lib_dir_called = false
    local function ensure_lib_dir() ensure_lib_dir_called = true end
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
    local dep_url = "https://raw.githubusercontent.com/owner/repo/branch/path/to/baz.lua"
    add_mod.add_dependency(nil, dep_url, load_manifest, save_manifest, ensure_lib_dir, downloader)
    assert.is_true(save_called)
    assert.are.equal(saved_manifest.dependencies["baz"], dep_url)
    assert.is_true(ensure_lib_dir_called)
    assert.is_true(downloader_called)
    assert.are.equal(downloader_args.url, dep_url)
    assert.are.equal(downloader_args.out_path, "src/lib/baz.lua")
  end)
end)
