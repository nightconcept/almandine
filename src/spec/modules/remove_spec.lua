--[[
  Remove Command Specification

  Busted test suite for the remove command in src/modules/remove.lua.
  - Verifies dependencies are removed from project.lua and files are deleted.
  - Handles both existing and non-existent dependencies.
]]
--

-- luacheck: globals describe it after_each assert

--- Remove module specification for Busted.
-- @module remove_spec

local remove_module = require("modules.remove")
local manifest_loader = require("utils.manifest")

local TEST_DEP_NAME = "testdep"
local TEST_DEP_PATH = "src/lib/testdep.lua"
local MANIFEST_FILE = "project.lua"

describe("remove_module.remove_dependency", function()
  local function write_manifest(deps)
    local file = assert(io.open(MANIFEST_FILE, "w"))
    file:write("return {\n")
    file:write('  name = "testproj",\n')
    file:write('  type = "application",\n')
    file:write('  version = "0.1.0",\n')
    file:write('  license = "MIT",\n')
    file:write('  description = "Test manifest",\n')
    file:write("  scripts = {},\n")
    file:write("  dependencies = {\n")
    for k, v in pairs(deps) do
      if type(v) == "table" then
        file:write(string.format("    [%q] = {", k))
        for tkey, tval in pairs(v) do
          file:write(string.format(" %s = %q,", tkey, tval))
        end
        file:write(" },\n")
      else
        file:write(string.format("    [%q] = %q,\n", k, v))
      end
    end
    file:write("  }\n")
    file:write("}\n")
    file:close()
  end

  local function file_exists(path)
    local f = io.open(path, "r")
    if f then
      f:close()
      return true
    end
    return false
  end

  local function cleanup()
    os.remove(MANIFEST_FILE)
    os.remove(TEST_DEP_PATH)
  end

  after_each(cleanup)

  it("removes existing dependency and deletes file", function()
    write_manifest({ [TEST_DEP_NAME] = "dummy_source" })
    os.execute("mkdir -p src/lib >nul 2>&1 || true")
    local f = assert(io.open(TEST_DEP_PATH, "w"))
    f:write("dummy content")
    f:close()
    assert.is_true(file_exists(TEST_DEP_PATH))
    local function save_manifest(m)
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
    remove_module.remove_dependency(TEST_DEP_NAME, manifest_loader.safe_load_project_manifest, save_manifest)
    local manifest = manifest_loader.safe_load_project_manifest()
    -- TODO: Check for nil value before using result
    assert.is_not_nil(manifest)
    assert.is_nil((manifest.dependencies or {})[TEST_DEP_NAME])
    assert.is_false(file_exists(TEST_DEP_PATH))
  end)

  it("does not error when removing nonexistent dependency", function()
    write_manifest({})
    assert.has_no.errors(function()
      remove_module.remove_dependency("doesnotexist", manifest_loader.safe_load_project_manifest, function(m)
        return write_manifest(m.dependencies or {})
      end)
    end)
  end)

  it("prints error when manifest fails to load", function()
    local printed = {}
    local stub = require("luassert.stub")
    local print_stub = stub(_G, "print", function(msg)
      table.insert(printed, tostring(msg))
    end)
    local function load_fail()
      return nil, "load error!"
    end
    local save_manifest = function()
      error("should not be called")
    end
    remove_module.remove_dependency(TEST_DEP_NAME, load_fail, save_manifest)
    print_stub:revert()
    assert.is_not_nil(table.concat(printed, "\n"):match("load error!"))
  end)
  it("prints error when save_manifest fails", function()
    write_manifest({ [TEST_DEP_NAME] = "dummy_source" })
    os.execute("mkdir -p src/lib >nul 2>&1 || true")
    local f = assert(io.open(TEST_DEP_PATH, "w"))
    f:write("dummy content")
    f:close()
    local printed = {}
    local stub = require("luassert.stub")
    local print_stub = stub(_G, "print", function(msg)
      table.insert(printed, tostring(msg))
    end)
    local function save_fail()
      return false, "save failed!"
    end
    remove_module.remove_dependency(TEST_DEP_NAME, manifest_loader.safe_load_project_manifest, save_fail)
    print_stub:revert()
    assert.is_not_nil(table.concat(printed, "\n"):match("save failed!"))
    assert.is_true(file_exists(TEST_DEP_PATH)) -- file should not be deleted
  end)
  it("removes dependency with custom .path", function()
    local dep_path = "src/lib/customdep.lua"
    write_manifest({ customdep = { url = "url", path = dep_path } })
    os.execute("mkdir -p src/lib >nul 2>&1 || true")
    local f = assert(io.open(dep_path, "w"))
    f:write("dummy content")
    f:close()
    local function save_manifest(m)
      write_manifest(m.dependencies or {})
      return true, nil
    end
    remove_module.remove_dependency("customdep", manifest_loader.safe_load_project_manifest, save_manifest)
    assert.is_false(file_exists(dep_path))
    local manifest = manifest_loader.safe_load_project_manifest()
    assert.is_nil((manifest.dependencies or {}).customdep)
  end)
  it("removes dependency using _G.dependency_add_test_paths", function()
    _G.dependency_add_test_paths = { foo = "src/lib/foo_testpath.lua" }
    write_manifest({ foo = "url" })
    os.execute("mkdir -p src/lib >nul 2>&1 || true")
    local f = assert(io.open("src/lib/foo_testpath.lua", "w"))
    f:write("dummy content")
    f:close()
    local function save_manifest(m)
      write_manifest(m.dependencies or {})
      return true, nil
    end
    remove_module.remove_dependency("foo", manifest_loader.safe_load_project_manifest, save_manifest)
    assert.is_false(file_exists("src/lib/foo_testpath.lua"))
    local manifest = manifest_loader.safe_load_project_manifest()
    assert.is_nil((manifest.dependencies or {}).foo)
    _G.dependency_add_test_paths = nil
  end)
  it("warns if file cannot be deleted", function()
    write_manifest({ bar = "url" })
    local printed = {}
    local stub = require("luassert.stub")
    local print_stub = stub(_G, "print", function(msg)
      table.insert(printed, tostring(msg))
    end)
    local function save_manifest(m)
      write_manifest(m.dependencies or {})
      return true, nil
    end
    -- do not create the file
    remove_module.remove_dependency("bar", manifest_loader.safe_load_project_manifest, save_manifest)
    print_stub:revert()
    local output = table.concat(printed, "\n")
    assert.is_not_nil(output:match("Warning: Could not delete file"))
  end)
  it("prints help_info output", function()
    local printed = {}
    local stub = require("luassert.stub")
    local print_stub = stub(_G, "print", function(msg)
      table.insert(printed, tostring(msg))
    end)
    assert.has_no.errors(function()
      remove_module.help_info()
    end)
    print_stub:revert()
    assert.is_not_nil(table.concat(printed, "\n"):match("Usage: almd remove"))
  end)
end)
