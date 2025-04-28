--[[
  Update Module Specification

  Busted test suite for update_dependencies in src/modules/update.lua.
  - Verifies update to latest allowed and absolute latest versions.
  - Uses stubs/mocks for manifest, downloader, and resolver.
]]
--

-- luacheck: globals describe it assert
-- local busted = require("busted")  -- unused

--- Update module specification for Busted.
-- @module update_spec

describe("update_module.update_dependencies", function()
  local update_module = require("modules.update")

  it("updates dependency to latest allowed version", function()
    local manifest = { dependencies = { foo = "https://example.com/foo.lua" } }
    local function load()
      return manifest
    end
    local function save(_) -- luacheck: ignore
      manifest = _
    end
    local function ensure_lib_dir1() end
    local utils = { downloader = {
      download = function()
        return true
      end,
    } }
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
    local function load()
      return manifest
    end
    local function save(_) -- luacheck: ignore
    end
    local function ensure_lib_dir2() end
    local utils = { downloader = {
      download = function()
        return true
      end,
    } }
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
          url = "https://example.com/foo.lua",
        },
      },
    }
    local function load()
      return manifest
    end
    local function save(_) -- luacheck: ignore
      manifest = _
    end
    local function ensure_lib_dir3() end
    local utils = { downloader = {
      download = function()
        return true
      end,
    } }
    local function resolve_latest_version(_name)
      return "2.0.0"
    end
    update_module.update_dependencies(load, save, ensure_lib_dir3, utils, resolve_latest_version)
    assert.are.equal(manifest.dependencies.foo.version, "2.0.0")
    assert.are.equal(manifest.dependencies.foo.url, "https://example.com/foo.lua")
  end)

  it("prints error and returns if manifest fails to load", function()
    local function load()
      return nil, "manifest error!"
    end
    local function save(_) -- luacheck: ignore
      error("should not save on manifest load error")
    end
    local ensure_lib_dir = function() end
    local utils = { downloader = {
      download = function()
        error("should not download")
      end,
    } }
    local resolve_latest_version = function()
      error("should not resolve")
    end
    local printed = {}
    local printer = function(...)
      local args = { ... }
      for i = 1, #args do
        args[i] = tostring(args[i])
      end
      table.insert(printed, table.concat(args, " "))
    end
    update_module.update_dependencies(load, save, ensure_lib_dir, utils, resolve_latest_version, nil, printer)
    local output = table.concat(printed, "\n")
    assert.is_true(output:find("manifest error!", 1, true) ~= nil)
  end)

  it("does not update or save if dependency already up-to-date", function()
    local manifest = { dependencies = { foo = { version = "1.3.4", url = "https://example.com/foo.lua" } } }
    local function load()
      return manifest
    end
    local function save(_) -- luacheck: ignore
    end
    local ensure_lib_dir = function() end
    local utils =
      { downloader = {
        download = function()
          error("should not download if up-to-date")
        end,
      } }
    local resolve_latest_version = function(_name)
      return "1.3.4"
    end
    update_module.update_dependencies(load, save, ensure_lib_dir, utils, resolve_latest_version)
    assert.are.equal(manifest.dependencies.foo.version, "1.3.4")
  end)

  it("prints download failure and continues", function()
    local manifest = {
      dependencies = {
        foo = "https://example.com/foo.lua",
        bar = {
          url = "https://example.com/bar.lua",
        },
      },
    }
    local function load()
      return manifest
    end
    local function save(_) -- luacheck: ignore
    end
    local ensure_lib_dir = function() end
    local utils = {
      downloader = {
        download = function(url, _)
          if url:find("foo") then
            return false, "network fail"
          end
          return true
        end,
      },
    }
    local resolve_latest_version = function(_)
      return "2.0.0"
    end
    local printed = {}
    local printer = function(...)
      local args = { ... }
      for i = 1, #args do
        args[i] = tostring(args[i])
      end
      table.insert(printed, table.concat(args, " "))
    end
    update_module.update_dependencies(load, save, ensure_lib_dir, utils, resolve_latest_version, nil, printer)
    local output = table.concat(printed, "\n")
    assert.is_true(output:find("Failed to download foo: network fail", 1, true) ~= nil)
    assert.are.equal(manifest.dependencies.foo.version, "2.0.0")
    assert.are.equal(manifest.dependencies.bar.version, "2.0.0")
  end)

  it("handles empty dependencies table", function()
    local manifest = { dependencies = {} }
    local function load()
      return manifest
    end
    local function save(_) -- luacheck: ignore
    end
    local ensure_lib_dir = function() end
    local utils =
      { downloader = {
        download = function()
          error("should not download if empty")
        end,
      } }
    local resolve_latest_version = function()
      error("should not resolve if empty")
    end
    update_module.update_dependencies(load, save, ensure_lib_dir, utils, resolve_latest_version)
    assert.are.same({}, manifest.dependencies)
  end)

  it("converts string dependency to table and updates version", function()
    local manifest = { dependencies = { foo = "https://example.com/foo.lua" } }
    local function load()
      return manifest
    end
    local function save(_) -- luacheck: ignore
      manifest = _
    end
    local ensure_lib_dir = function() end
    local utils = { downloader = {
      download = function()
        return true
      end,
    } }
    local resolve_latest_version = function(_)
      return "9.9.9"
    end
    update_module.update_dependencies(load, save, ensure_lib_dir, utils, resolve_latest_version)
    assert.are.same({ version = "9.9.9", url = "https://example.com/foo.lua" }, manifest.dependencies.foo)
  end)

  it("writes to default out_path if not specified in dependency table", function()
    local manifest = { dependencies = { foo = { version = "1.0.0", url = "https://example.com/foo.lua" } } }
    local function load()
      return manifest
    end
    local function save(_) -- luacheck: ignore
      manifest = _
    end
    local ensure_lib_dir = function() end
    local called_out_path
    local utils = {
      downloader = {
        download = function(_, out_path)
          called_out_path = out_path
          return true
        end,
      },
    }
    local resolve_latest_version = function(_)
      return "2.0.0"
    end
    update_module.update_dependencies(load, save, ensure_lib_dir, utils, resolve_latest_version)
    assert.are.equal("src/lib/foo.lua", called_out_path)
  end)

  it("writes to specified out_path if present in dependency table", function()
    local manifest = {
      dependencies = { foo = { version = "1.0.0", url = "https://example.com/foo.lua", path = "custom/foo.lua" } },
    }
    local function load()
      return manifest
    end
    local function save(_) -- luacheck: ignore
      manifest = _
    end
    local ensure_lib_dir = function() end
    local called_out_path
    local utils = {
      downloader = {
        download = function(_, out_path)
          called_out_path = out_path
          return true
        end,
      },
    }
    local resolve_latest_version = function(_)
      return "2.0.0"
    end
    update_module.update_dependencies(load, save, ensure_lib_dir, utils, resolve_latest_version)
    assert.are.equal("custom/foo.lua", called_out_path)
  end)

  it("prints update message when dependency is updated", function()
    local manifest = { dependencies = { foo = "https://example.com/foo.lua" } }
    local function load()
      return manifest
    end
    local function save(_) -- luacheck: ignore
      manifest = _
    end
    local ensure_lib_dir = function() end
    local utils = { downloader = {
      download = function()
        return true
      end,
    } }
    local resolve_latest_version = function(_)
      return "3.1.4"
    end
    local printed = {}
    local printer = function(...)
      local args = { ... }
      for i = 1, #args do
        args[i] = tostring(args[i])
      end
      table.insert(printed, table.concat(args, " "))
    end
    update_module.update_dependencies(load, save, ensure_lib_dir, utils, resolve_latest_version, nil, printer)
    local output = table.concat(printed, "\n")
    assert.is_true(output:find("Updating foo from", 1, true) ~= nil)
    assert.is_true(output:find("3.1.4", 1, true) ~= nil)
    assert.are.equal(manifest.dependencies.foo.version, "3.1.4")
  end)
end)
