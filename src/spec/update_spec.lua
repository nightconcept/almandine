--[[
  Update Module Specification

  Busted test suite for update_dependencies in src/modules/update.lua.
  - Verifies update to latest allowed and absolute latest versions.
  - Uses stubs/mocks for manifest, downloader, and resolver.
]]--

--- Update module specification for Busted.
-- @module update_spec

describe("update_module.update_dependencies", function()
  local update_module = require("modules.update")
  local update_dependencies = update_module.update_dependencies

  local function make_manifest()
    local manifest = { dependencies = { foo = "https://example.com/foo.lua" } }
    return function() return manifest end, function(new_manifest) manifest = new_manifest return true end, function() return manifest end
  end

  local function ensure_lib_dir() end

  local function make_downloader()
    local downloads = {}
    return {
      download = function(url, out_path)
        table.insert(downloads, {url=url, out_path=out_path})
        if url and out_path then return true end
        return false, "invalid args"
      end,
      get_downloads = function() return downloads end
    }
  end

  local function make_resolver()
    return function(name, source, latest)
      if latest then
        return "2.0.0", "https://example.com/foo-latest.lua"
      else
        return "1.3.4", "https://example.com/foo-1.3.4.lua"
      end
    end
  end

  it("updates dependency to latest allowed version", function()
    local manifest = { dependencies = { foo = "https://example.com/foo.lua" } }
    local function load() return manifest end
    local function save(tbl) manifest = tbl end
    local function ensure_lib_dir() end
    local utils = { downloader = { download = function() return true end } }
    local function resolve_latest_version(name)
      return "1.3.4"
    end
    update_module.update_dependencies(load, save, ensure_lib_dir, utils, resolve_latest_version)
    -- After update, manifest.dependencies.foo should be a table with version and url
    assert.are.equal(manifest.dependencies.foo.version, "1.3.4")
    assert.are.equal(manifest.dependencies.foo.url, "https://example.com/foo.lua")
  end)

  it("updates dependency to absolute latest version", function()
    local manifest = { dependencies = { foo = "https://example.com/foo.lua" } }
    local function load() return manifest end
    local function save(tbl) manifest = tbl end
    local function ensure_lib_dir() end
    local utils = { downloader = { download = function() return true end } }
    local function resolve_latest_version(name)
      return "latest"
    end
    update_module.update_dependencies(load, save, ensure_lib_dir, utils, resolve_latest_version, true)
    assert.are.equal(manifest.dependencies.foo.version, "latest")
    assert.are.equal(manifest.dependencies.foo.url, "https://example.com/foo.lua")
  end)

  it("updates dependency versions in manifest", function()
    local manifest = { dependencies = { foo = { version = "1.0.0", url = "https://example.com/foo.lua" } } }
    local function load() return manifest end
    local function save(tbl) manifest = tbl end
    local function ensure_lib_dir() end
    local utils = { downloader = { download = function() return true end } }
    local function resolve_latest_version(name)
      return "2.0.0"
    end
    update_module.update_dependencies(load, save, ensure_lib_dir, utils, resolve_latest_version)
    assert.are.equal(manifest.dependencies.foo.version, "2.0.0")
    assert.are.equal(manifest.dependencies.foo.url, "https://example.com/foo.lua")
  end)
end)
