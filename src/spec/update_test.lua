--[[
  Update module tests for Almandine

  Verifies correct behavior of the update_dependencies function in modules/update.lua.
  No external dependencies. All output is checked for correctness and reproducibility.
]]--

package.path = package.path .. ";./src/?.lua;./src/?/init.lua;./src/?/?.lua"

local update = require("modules.update")
local update_dependencies = update.update_dependencies

--- Dummy manifest loader/saver for testing.
local function make_manifest()
  local manifest = { dependencies = { foo = "https://example.com/foo.lua" } }
  return function() return manifest end, function(new_manifest) manifest = new_manifest return true end, function() return manifest end
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

--- Dummy resolver: simulates version resolution
local function make_resolver()
  return function(name, source, latest)
    if latest then
      return "2.0.0", "https://example.com/foo-latest.lua"
    else
      return "1.3.4", "https://example.com/foo-1.3.4.lua"
    end
  end
end

-- Test: Update dependency to latest allowed version
local function test_update_default()
  local load, save = make_manifest()
  local downloader = make_downloader()
  local resolve_latest_version = make_resolver()
  update_dependencies(load, save, ensure_lib_dir, downloader, resolve_latest_version, false)
  local downloads = downloader.get_downloads()
  if #downloads == 1 and downloads[1].url == "https://example.com/foo-1.3.4.lua" then
    print("[PASS] Update to latest allowed version works.")
  else
    print("[FAIL] Update to latest allowed version failed.")
  end
end

-- Test: Update dependency to absolute latest version
local function test_update_latest()
  local load, save = make_manifest()
  local downloader = make_downloader()
  local resolve_latest_version = make_resolver()
  update_dependencies(load, save, ensure_lib_dir, downloader, resolve_latest_version, true)
  local downloads = downloader.get_downloads()
  if #downloads == 1 and downloads[1].url == "https://example.com/foo-latest.lua" then
    print("[PASS] Update to absolute latest version works.")
  else
    print("[FAIL] Update to absolute latest version failed.")
  end
end

test_update_default()
test_update_latest()
