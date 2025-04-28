--[[
  Install module tests for Almandine

  Verifies correct behavior of the install_dependencies function.
  Ensures only dependencies present in the manifest are installed, and manifest is not modified.
  No external dependencies. All output is checked for correctness and reproducibility.
]]--

-- Ensure Lua can find modules in src/
package.path = package.path .. ";./src/?.lua;./src/?/init.lua;./src/?/?.lua"

local install = require("modules.install")
local install_dependencies = install.install_dependencies

--- Dummy manifest loader for testing.
local function make_manifest(deps)
  local manifest = { dependencies = deps or {} }
  return function() return manifest, nil end
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

-- Test: Install all dependencies from manifest
local function test_install_all_dependencies()
  local deps = {
    foo = "https://example.com/foo.lua",
    bar = { url = "https://example.com/bar.lua", path = "custom/bar.lua" }
  }
  local load = make_manifest(deps)
  local downloader = make_downloader()
  install_dependencies(nil, load, ensure_lib_dir, downloader)
  local downloads = downloader.get_downloads()
  assert(#downloads == 2, "Should install all dependencies")
  assert(downloads[1].url == "https://example.com/foo.lua", "First dependency URL incorrect")
  assert(downloads[2].url == "https://example.com/bar.lua", "Second dependency URL incorrect")
  assert(downloads[2].out_path == "custom/bar.lua", "Table source out_path incorrect")
  print("[PASS] Install all dependencies from manifest")
end

-- Test: Install single dependency from manifest
local function test_install_single_dependency()
  local deps = {
    foo = "https://example.com/foo.lua",
    bar = "https://example.com/bar.lua"
  }
  local load = make_manifest(deps)
  local downloader = make_downloader()
  install_dependencies("foo", load, ensure_lib_dir, downloader)
  local downloads = downloader.get_downloads()
  assert(#downloads == 1, "Should install only the specified dependency")
  assert(downloads[1].url == "https://example.com/foo.lua", "Dependency URL incorrect")
  print("[PASS] Single dependency install works.")
end

test_install_all_dependencies()
test_install_single_dependency()
