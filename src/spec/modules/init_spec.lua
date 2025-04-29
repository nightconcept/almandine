--[[
  Spec for src/modules/init.lua

  Tests the interactive project initialization and manifest creation logic.
  Mocks user input and file system side effects to ensure non-interactive, deterministic tests.
]]--

local init = require("modules.init")
local manifest_utils = require("utils.manifest")

local stub = require("luassert.stub")
local spy = require("luassert.spy")

-- Helper to mock io.read for prompts
local function with_mocked_io_read(inputs, fn)
  local idx = 0
  local io_read_stub = stub(io, "read", function()
    idx = idx + 1
    return inputs[idx] or ""
  end)
  local ok, err = pcall(fn)
  io_read_stub:revert()
  if not ok then error(err) end
end

describe("modules.init", function()
  it("prints help info", function()
    local print_spy = spy.on(_G, "print")
    init.help_info()
    assert.spy(print_spy).was.called_with(match.is_string())
    print_spy:revert()
  end)

  it("initializes a project and writes manifest (happy path)", function()
    local fake_inputs = {
      "TestProject", -- name
      "1.2.3",       -- version
      "Apache-2.0",  -- license
      "A test proj", -- description
      "build",       -- script name
      "make build",  -- script cmd
      "",            -- end scripts
      "dep1",        -- dep name
      "^1.0.0",      -- dep version
      "",            -- end deps
    }
    local saved_manifest
    local save_manifest_stub = stub(manifest_utils, "save_manifest", function(m)
      saved_manifest = m
      return true
    end)
    local print_spy = spy.on(_G, "print")
    with_mocked_io_read(fake_inputs, function()
      init.init_project()
    end)
    assert.same(saved_manifest.name, "TestProject")
    assert.same(saved_manifest.version, "1.2.3")
    assert.same(saved_manifest.license, "Apache-2.0")
    assert.same(saved_manifest.description, "A test proj")
    assert.same(saved_manifest.scripts.build, "make build")
    assert.same(saved_manifest.scripts.run, "lua src/main.lua")
    assert.same(saved_manifest.dependencies.dep1, "^1.0.0")
    assert.stub(save_manifest_stub).was.called(1)
    assert.spy(print_spy).was.called_with(match.is_string())
    save_manifest_stub:revert()
    print_spy:revert()
  end)

  it("handles manifest write failure", function()
    local fake_inputs = {"N", "", "", "", "", "", ""}
    local save_manifest_stub = stub(manifest_utils, "save_manifest", function()
      return false, "write error"
    end)
    local print_spy = spy.on(_G, "print")
    local exit_stub = stub(os, "exit", function(code) _G.exit_called = code end)
    with_mocked_io_read(fake_inputs, function()
      init.init_project()
    end)
    assert.stub(save_manifest_stub).was.called(1)
    assert.spy(print_spy).was.called_with(match.is_string())
    assert.same(_G.exit_called, 1)
    save_manifest_stub:revert()
    print_spy:revert()
    exit_stub:revert()
    _G.exit_called = nil
  end)

  it("always sets default 'run' script if not provided", function()
    local fake_inputs = {"Proj", "", "", "", "", "", ""}
    local saved_manifest
    local save_manifest_stub = stub(manifest_utils, "save_manifest", function(m)
      saved_manifest = m
      return true
    end)
    with_mocked_io_read(fake_inputs, function()
      init.init_project()
    end)
    assert.same(saved_manifest.scripts.run, "lua src/main.lua")
    save_manifest_stub:revert()
  end)

  it("allows user to override default 'run' script", function()
    local fake_inputs = {"Proj", "", "", "", "run", "custom run", "", "", ""}
    local saved_manifest
    local save_manifest_stub = stub(manifest_utils, "save_manifest", function(m)
      saved_manifest = m
      return true
    end)
    with_mocked_io_read(fake_inputs, function()
      init.init_project()
    end)
    assert.same(saved_manifest.scripts.run, "custom run")
    save_manifest_stub:revert()
  end)
end)
