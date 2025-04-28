--[[
  Update Module Specification

  Busted test suite for update_dependencies in src/modules/update.lua.
  - Verifies update to latest allowed and absolute latest versions.
  - Uses stubs/mocks for manifest, downloader, and resolver.
]]--

-- luacheck: globals describe it assert
-- local busted = require("busted")  -- unused

--- Update module specification for Busted.
-- @module update_spec

describe("update_module.update_dependencies", function()
  local update_module = require("modules.update")

  it("updates dependency to latest allowed version", function()
    local manifest = { dependencies = { foo = "https://example.com/foo.lua" } }
    local function load() return manifest end
    local function save(tbl) manifest = tbl end
    local function ensure_lib_dir1() end
    local utils = { downloader = { download = function() return true end } }
    local function resolve_latest_version(_name)
      return "1.3.4"
    end
    update_module.update_dependencies(load, save, ensure_lib_dir1, utils, resolve_latest_version)
    -- After update, manifest.dependencies.foo should be a table with version and url
    assert.are.equal(manifest.dependencies.foo.version, "1.3.4")
    assert.are.equal(manifest.dependencies.foo.url, "https://example.com/foo.lua")
  end)

  it("updates dependency to absolute latest version", function()
    local manifest = { dependencies = { foo = "https://example.com/foo.lua" } }
    local function load() return manifest end
    local function save(tbl) manifest = tbl end
    local function ensure_lib_dir2() end
    local utils = { downloader = { download = function() return true end } }
    local function resolve_latest_version(_name)
      return "latest"
    end
    update_module.update_dependencies(load, save, ensure_lib_dir2, utils, resolve_latest_version, true)
    assert.are.equal(manifest.dependencies.foo.version, "latest")
    assert.are.equal(manifest.dependencies.foo.url, "https://example.com/foo.lua")
  end)

  it("updates dependency versions in manifest", function()
    local manifest = {
      dependencies = {
        foo = {
          version = "1.0.0",
          url = "https://example.com/foo.lua"
        }
      }
    }
    local function load() return manifest end
    local function save(tbl) manifest = tbl end
    local function ensure_lib_dir3() end
    local utils = { downloader = { download = function() return true end } }
    local function resolve_latest_version(_name)
      return "2.0.0"
    end
    update_module.update_dependencies(load, save, ensure_lib_dir3, utils, resolve_latest_version)
    assert.are.equal(manifest.dependencies.foo.version, "2.0.0")
    assert.are.equal(manifest.dependencies.foo.url, "https://example.com/foo.lua")
  end)
end)
