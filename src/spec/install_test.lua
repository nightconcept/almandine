--[[
  Install module tests for Almandine

  Verifies correct behavior of the install_dependency function.
  No external dependencies. All output is checked for correctness and reproducibility.
]]--

-- Ensure Lua can find modules in src/
package.path = package.path .. ";./src/?.lua;./src/?/init.lua;./src/?/?.lua"

local install = require("modules.install")
local install_dependency = install.install_dependency

--- Dummy manifest loader/saver for testing.
local function make_manifest()
  local manifest = { dependencies = {} }
  return function() return manifest end, function(new_manifest) manifest = new_manifest return true end
end

--- Dummy ensure_lib_dir (no-op for test)
local function ensure_lib_dir() end

--- Dummy downloader: records downloads and simulates success/failure
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

-- Test: Add and install a new dependency
local function test_install_single_dependency()
  local load, save = make_manifest()
  local downloader = make_downloader()
  install_dependency("foo", "https://example.com/foo.lua", load, save, ensure_lib_dir, downloader)
  local downloads = downloader.get_downloads()
  if #downloads == 1 and downloads[1].url == "https://example.com/foo.lua" then
    print("[PASS] Single dependency install works.")
  else
    print("[FAIL] Single dependency install failed.")
  end
end

test_install_single_dependency()
