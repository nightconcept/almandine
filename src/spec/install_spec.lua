--[[
  Install Module Specification

  Busted test suite for install_dependencies in src/modules/install.lua.
  - Verifies correct installation of dependencies from manifest.
  - Ensures manifest is not modified and only manifest dependencies are installed.
]]--

-- luacheck: globals describe it assert

local busted = require("busted")

--- Install module specification for Busted.
-- @module install_spec

describe("install_module.install_dependencies", function()
  local install = require("modules.install")
  local install_dependencies = install.install_dependencies

  local function make_manifest(deps)
    local manifest = { dependencies = deps or {} }
    return function() return manifest, nil end
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

  it("installs all dependencies from manifest", function()
    local deps = {
      foo = "https://example.com/foo.lua",
      bar = { url = "https://example.com/bar.lua", path = "custom/bar.lua" }
    }
    local load = make_manifest(deps)
    local downloader = make_downloader()
    local utils = {downloader = downloader}
    install_dependencies(nil, load, ensure_lib_dir, downloader, utils)
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

  it("installs only the specified dependency", function()
    local deps = {
      foo = "https://example.com/foo.lua",
      bar = "https://example.com/bar.lua"
    }
    local load = make_manifest(deps)
    local downloader = make_downloader()
    local utils = {downloader = downloader}
    install_dependencies("foo", load, ensure_lib_dir, downloader, utils)
    local downloads = downloader.get_downloads()
    assert.are.equal(#downloads, 1)
    assert.are.equal(downloads[1].url, "https://example.com/foo.lua")
  end)
end)
