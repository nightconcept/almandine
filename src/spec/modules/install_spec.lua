--[[
  Install Module Specification

  Busted test suite for install_dependencies in src/modules/install.lua.
  - Verifies correct installation of dependencies from manifest.
  - Ensures manifest is not modified and only manifest dependencies are installed.
]]
--

-- luacheck: globals describe it assert

--- Install module specification for Busted.
-- @module install_spec

describe("install_module.install_dependencies", function()
  local install_mod = require("modules.install")
  local install_dependencies = install_mod.install_dependencies

  local function make_manifest(deps)
    local manifest = { dependencies = deps or {} }
    return function()
      return manifest, nil
    end
  end

  local function ensure_lib_dir() end

  local function make_downloader()
    local downloads = {}
    return {
      download = function(url, out_path)
        table.insert(downloads, { url = url, out_path = out_path })
        if url and out_path then
          return true
        end
        return false, "invalid args"
      end,
      get_downloads = function()
        return downloads
      end,
    }
  end

  it("installs all dependencies from manifest", function()
    local deps = {
      foo = "https://example.com/foo.lua",
      bar = { url = "https://example.com/bar.lua", path = "custom/bar.lua" },
    }
    local load = make_manifest(deps)
    local downloader = make_downloader()
    local utils = { downloader = downloader }
    install_dependencies(nil, load, ensure_lib_dir, downloader, utils)
    local downloads = downloader.get_downloads()
    assert.are.equal(#downloads, 2)
    local found_foo, found_bar, found_custom = false, false, false
    for _, d in ipairs(downloads) do
      if d.url == "https://example.com/foo.lua" then
        found_foo = true
      end
      if d.url == "https://example.com/bar.lua" then
        found_bar = true
      end
      if d.out_path == "custom/bar.lua" then
        found_custom = true
      end
    end
    assert.is_true(found_foo and found_bar and found_custom)
  end)

  it("installs only the specified dependency", function()
    local deps = {
      foo = "https://example.com/foo.lua",
      bar = "https://example.com/bar.lua",
    }
    local load = make_manifest(deps)
    local downloader = make_downloader()
    local utils = { downloader = downloader }
    install_dependencies("foo", load, ensure_lib_dir, downloader, utils)
    local downloads = downloader.get_downloads()
    assert.are.equal(#downloads, 1)
    assert.are.equal(downloads[1].url, "https://example.com/foo.lua")
  end)

  it("installs from lockfile_deps table", function()
    local lockfile_deps = {
      foo = "https://example.com/foo.lua",
      bar = { url = "https://example.com/bar.lua", path = "custom/bar.lua" },
    }
    local load = function() error("should not call load_manifest when lockfile_deps provided") end
    local downloader = make_downloader()
    local utils = { downloader = downloader }
    install_dependencies(nil, load, ensure_lib_dir, downloader, utils, lockfile_deps)
    local downloads = downloader.get_downloads()
    assert.are.equal(#downloads, 2)
    local found_foo, found_bar, found_custom = false, false, false
    for _, d in ipairs(downloads) do
      if d.url == "https://example.com/foo.lua" then found_foo = true end
      if d.url == "https://example.com/bar.lua" then found_bar = true end
      if d.out_path == "custom/bar.lua" then found_custom = true end
    end
    assert.is_true(found_foo and found_bar and found_custom)
  end)

  it("prints error and returns if manifest fails to load", function()
    local load = function() return nil, "load error!" end
    local downloader = make_downloader()
    local utils = { downloader = downloader }
    local printed = nil
    local print_stub = require("luassert.stub")(_G, "print", function(msg) printed = msg end)
    install_dependencies(nil, load, ensure_lib_dir, downloader, utils)
    print_stub:revert()
    assert.is_true(type(printed) == "string" and printed:match("load error!"))
    assert.is_true(type(#downloader.get_downloads()) == "number" and #downloader.get_downloads() == 0)
  end)

  describe("lockfile submodule", function()
    local lockfile = install_mod.lockfile

    it("generates lockfile table with all fields", function()
      local resolved = {
        foo = { hash = "abc", version = "1.0", source = "src" },
        bar = { hash = "def" },
      }
      local tbl = lockfile.generate_lockfile_table(resolved)
      assert.are.equal(tbl.api_version, "1")
      assert.is_table(tbl.package)
      assert.are.equal(tbl.package.foo.hash, "abc")
      assert.are.equal(tbl.package.foo.version, "1.0")
      assert.are.equal(tbl.package.foo.source, "src")
      assert.are.equal(tbl.package.bar.hash, "def")
    end)

    it("errors if resolved_deps is not a table", function()
      assert.has_error(function() lockfile.generate_lockfile_table(nil) end)
    end)

    it("errors if dependency entry is not a table", function()
      local resolved = { foo = "notatable" }
      assert.has_error(function() lockfile.generate_lockfile_table(resolved) end)
    end)

    it("errors if dependency entry is missing hash", function()
      local resolved = { foo = {} }
      assert.has_error(function() lockfile.generate_lockfile_table(resolved) end)
    end)

    it("serializes lockfile table to Lua string", function()
      local tbl = { api_version = "1", package = { foo = { hash = "abc" } } }
      local str = lockfile.serialize_lockfile(tbl)
      assert.is_true(type(str) == "string" and str:match("return"))
    end)

    it("errors if serialize_lockfile arg is not a table", function()
      assert.has_error(function() lockfile.serialize_lockfile(nil) end)
    end)

    it("writes lockfile to disk and returns true", function()
      local tbl = { api_version = "1", package = { foo = { hash = "abc" } } }
      local io_stub = require("luassert.stub")(io, "open", function(_path, mode)
        assert.are.equal(mode, "w")
        return { write = function() end, close = function() end }, nil
      end)
      local ok, path_out = lockfile.write_lockfile(tbl, "test-lock.lua")
      io_stub:revert()
      assert.is_true(ok)
      assert.are.equal(path_out, "test-lock.lua")
    end)

    it("returns false and error if file cannot be opened", function()
      local tbl = { api_version = "1", package = { foo = { hash = "abc" } } }
      local io_stub = require("luassert.stub")(io, "open", function() return nil, "fail open" end)
      local ok, err = lockfile.write_lockfile(tbl, "bad-path")
      io_stub:revert()
      assert.is_false(ok)
      assert.are.equal(err, "fail open")
    end)
  end)

  it("prints help_info output", function()
    local help = install_mod.help_info
    local printed = {}
    local print_stub = require("luassert.stub")(_G, "print", function(msg) table.insert(printed, msg) end)
    help()
    print_stub:revert()
    assert.is_true(#printed > 0 and tostring(printed[1]):match("Usage: almd install"))
  end)
end)
