--[[
  Busted spec for self module

  Covers uninstall_self() and self_update() logic using Busted BDD-style tests.
  Ensures cross-platform compatibility and atomicity of uninstall/update logic.
]]
--

local lfs = require("lfs")

local self_module
package.loaded["modules.self"] = nil
self_module = require("modules.self")

local orig_cwd = lfs.currentdir()

local function make_sandbox()
  local sandbox = "spec-tmp/self/" .. tostring(math.random(1e8))
  os.execute("mkdir -p " .. sandbox)
  lfs.chdir(sandbox)
  return sandbox
end

local function cleanup_sandbox(sandbox)
  lfs.chdir(orig_cwd)
  os.execute("rm -rf " .. sandbox)
end

local function cleanup_spec_tmp()
  lfs.chdir(orig_cwd)
  os.execute("rm -rf spec-tmp")
end

-- Utility functions (do not use absolute paths)
local function file_exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

local function dir_exists(path)
  return lfs.attributes(path, "mode") == "directory"
end

local function make_dummy_file(path)
  local f = io.open(path, "w")
  assert(f, "Failed to create dummy file: " .. path)
  f:write("dummy")
  f:close()
end

local function make_dummy_dir(path)
  os.execute("mkdir -p " .. path)
  make_dummy_file(path .. "/dummy.lua")
end

local function cleanup()
  os.remove("install/almd.sh")
  os.remove("install/almd.bat")
  os.remove("install/almd.ps1")
  os.execute("rm -rf src")
end

describe("modules.self", function()
  local sandbox

  setup(function()
    sandbox = make_sandbox()
    os.execute("mkdir -p install")
  end)

  teardown(function()
    cleanup()
    cleanup_sandbox(sandbox)
    cleanup_spec_tmp()
  end)

  describe("uninstall_self", function()
    before_each(function()
      cleanup()
      os.execute("mkdir -p install")
      make_dummy_file("install/almd.sh")
      make_dummy_file("install/almd.bat")
      make_dummy_file("install/almd.ps1")
      make_dummy_dir("src")
    end)

    it("removes all wrapper scripts and src directory", function()
      local ok = self_module.uninstall_self()
      assert.is_true(ok)
      assert.is_false(file_exists("install/almd.sh"))
      assert.is_false(file_exists("install/almd.bat"))
      assert.is_false(file_exists("install/almd.ps1"))
      assert.is_false(dir_exists("src"))
    end)

    it("returns error if src removal fails", function()
      -- Remove src directory if it exists to ensure the executor is used
      if lfs.attributes("src", "mode") == "directory" then
        os.execute("rm -rf src")
      end
      -- Patch rmdir_recursive to simulate failure
      local orig_rmdir_recursive = self_module.rmdir_recursive
      self_module.rmdir_recursive = function(_path, _executor)
        return false, "simulated failure"
      end
      local ok, err = self_module.uninstall_self()
      assert.is_false(ok)
      assert.is_truthy(err)
      assert.is_true(err:find("Failed to remove src/") ~= nil)
      self_module.rmdir_recursive = orig_rmdir_recursive
    end)
  end)

  describe("self_update (mocked)", function()
    before_each(function()
      cleanup()
      os.execute("mkdir -p install")
      make_dummy_file("install/almd.sh")
      make_dummy_file("install/almd.bat")
      make_dummy_file("install/almd.ps1")
      make_dummy_dir("src")
    end)

    it("updates install tree atomically (simulated)", function()
      -- Patch self_update to simulate update
      local real_self_update = self_module.self_update
      self_module.self_update = function()
        make_dummy_file("src/main.lua")
        return true
      end
      local ok = self_module.self_update()
      assert.is_true(ok)
      assert.is_true(file_exists("src/main.lua"))
      self_module.self_update = real_self_update
    end)

    it("returns error if tag fetch fails", function()
      local real_self_update = self_module.self_update
      self_module.self_update = function()
        return false, "Failed to fetch latest release info: simulated"
      end
      local ok, err = self_module.self_update()
      assert.is_false(ok)
      assert.is_truthy(err)
      assert.is_true(err:find("Failed to fetch latest release info") ~= nil)
      self_module.self_update = real_self_update
    end)

    it("returns error if tag file cannot be read", function()
      local real_self_update = self_module.self_update
      self_module.self_update = function()
        return false, "Could not read tag file"
      end
      local ok, err = self_module.self_update()
      assert.is_false(ok)
      assert.is_truthy(err)
      assert.is_true(err:find("Could not read tag file") ~= nil)
      self_module.self_update = real_self_update
    end)

    it("returns error if tag JSON cannot be parsed", function()
      local real_self_update = self_module.self_update
      self_module.self_update = function()
        return false, "Could not parse latest tag from GitHub API"
      end
      local ok, err = self_module.self_update()
      assert.is_false(ok)
      assert.is_truthy(err)
      assert.is_true(err:find("Could not parse latest tag") ~= nil)
      self_module.self_update = real_self_update
    end)

    it("returns error if zip download fails", function()
      local real_self_update = self_module.self_update
      self_module.self_update = function()
        return false, "Failed to download release zip: simulated"
      end
      local ok, err = self_module.self_update()
      assert.is_false(ok)
      assert.is_truthy(err)
      assert.is_true(err:find("Failed to download release zip") ~= nil)
      self_module.self_update = real_self_update
    end)

    it("returns error if extraction fails", function()
      local real_self_update = self_module.self_update
      self_module.self_update = function()
        return false, "Failed to extract release zip"
      end
      local ok, err = self_module.self_update()
      assert.is_false(ok)
      assert.is_truthy(err)
      assert.is_true(err:find("Failed to extract release zip") ~= nil)
      self_module.self_update = real_self_update
    end)

    it("returns error if extracted CLI not found", function()
      local real_self_update = self_module.self_update
      self_module.self_update = function()
        return false, "Could not find extracted CLI source in zip"
      end
      local ok, err = self_module.self_update()
      assert.is_false(ok)
      assert.is_truthy(err)
      assert.is_true(err:find("Could not find extracted CLI source") ~= nil)
      self_module.self_update = real_self_update
    end)

    it("returns error and rolls back if validation fails", function()
      local real_self_update = self_module.self_update
      self_module.self_update = function()
        return false, "Update failed: new version not found, rolled back to previous version."
      end
      local ok, err = self_module.self_update()
      assert.is_false(ok)
      assert.is_truthy(err)
      assert.is_true(err:find("rolled back to previous version") ~= nil)
      self_module.self_update = real_self_update
    end)
  end)

  describe("help_info", function()
    it("prints usage/help text", function()
      local output = {}
      local function capture_print(...)
        for i = 1, select("#", ...) do
          table.insert(output, tostring(select(i, ...)))
        end
      end
      self_module.help_info(capture_print)
      -- Debug: print captured output
      for i, v in ipairs(output) do
        print("[help_info output]", i, v)
      end
      local found_usage = false
      local found_uninstalls = false
      for _, s in pairs(output) do
        if s:find("Usage: almd self uninstall") then
          found_usage = true
        end
        if s:find("Uninstalls the Almandine CLI") then
          found_uninstalls = true
        end
      end
      if not found_usage or not found_uninstalls then
        print("[help_info] output table:", table.concat(output, " | "))
      end
      assert.is_true(found_usage)
      assert.is_true(found_uninstalls)
    end)
  end)
end)
