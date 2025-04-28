--[[
  Remove Command Specification

  Busted test suite for the remove command in src/modules/remove.lua.
  - Verifies dependencies are removed from project.lua and files are deleted.
  - Handles both existing and non-existent dependencies.
]]--

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
end)
