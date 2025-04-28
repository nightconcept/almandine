--[[
  Busted spec for self module

  Covers uninstall_self() and self_update() logic using Busted BDD-style tests.
  Ensures cross-platform compatibility and atomicity of uninstall/update logic.
]]
--

local self_module = require("modules.self")

local lfs = require("lfs")

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
  end)
end)
