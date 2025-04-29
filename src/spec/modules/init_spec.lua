--[[
  Spec for src/modules/init.lua

  Comprehensive tests for interactive project initialization and manifest creation logic.
  All user input, file system, and process side effects are stubbed for deterministic, non-interactive tests.
  Follows project LDoc and style guidelines.
]]
--

local init = require("modules.init")
local manifest_utils = require("utils.manifest")

local stub = require("luassert.stub")
local spy = require("luassert.spy")

--- Helper: Mock io.read to provide scripted answers.
-- @param answers [table] List of answers to return (in order)
-- @param fn [function] Function to run with mocked io.read
local function with_mocked_io_read(answers, fn)
  local idx = 0
  local io_read_stub = stub(io, "read", function()
    idx = idx + 1
    return answers[idx] or ""
  end)
  local ok, err = pcall(fn)
  io_read_stub:revert()
  if not ok then
    error(err)
  end
end

--- Spec for modules.init
-- @class spec.modules.init

describe("modules.init", function()
  --- Test help_info prints usage text
  it("prints help info", function()
    local print_spy = spy.on(_G, "print")
    init.help_info()
    assert.spy(print_spy).was.called_with(match.is_string())
    print_spy:revert()
  end)

  --- Test happy path: all prompts, 1 script, 1 dependency
  it("initializes project and writes manifest (happy path)", function()
    local answers = {
      "MyProj", -- name
      "2.0.0", -- version
      "BSD-3", -- license
      "desc", -- description
      "build", -- script name
      "make build", -- script cmd
      "", -- end scripts
      "dep1", -- dep name
      "^1.0.0", -- dep version
      "", -- end deps
    }
    local saved_manifest
    local save_manifest_stub = stub(manifest_utils, "save_manifest", function(m)
      saved_manifest = m
      return true
    end)
    local print_spy = spy.on(_G, "print")
    with_mocked_io_read(answers, function()
      init.init_project()
    end)
    assert.same(saved_manifest.name, "MyProj")
    assert.same(saved_manifest.version, "2.0.0")
    assert.same(saved_manifest.license, "BSD-3")
    assert.same(saved_manifest.description, "desc")
    assert.same(saved_manifest.scripts.build, "make build")
    assert.same(saved_manifest.scripts.run, "lua src/main.lua")
    assert.same(saved_manifest.dependencies.dep1, "^1.0.0")
    assert.stub(save_manifest_stub).was.called(1)
    assert.spy(print_spy).was.called_with(match.is_string())
    save_manifest_stub:revert()
    print_spy:revert()
  end)

  --- Test: manifest write failure triggers error and exit
  it("handles manifest write failure", function()
    local answers = { "X", "", "", "", "", "", "" }
    local save_manifest_stub = stub(manifest_utils, "save_manifest", function()
      return false, "write error"
    end)
    local print_spy = spy.on(_G, "print")
    local exit_stub = stub(os, "exit", function(code)
      _G.exit_called = code
    end)
    with_mocked_io_read(answers, function()
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

  --- Test: no scripts provided, default 'run' script is set
  it("sets default 'run' script if not provided", function()
    local answers = { "P", "", "", "", "", "", "" }
    local saved_manifest
    local save_manifest_stub = stub(manifest_utils, "save_manifest", function(m)
      saved_manifest = m
      return true
    end)
    with_mocked_io_read(answers, function()
      init.init_project()
    end)
    assert.same(saved_manifest.scripts.run, "lua src/main.lua")
    save_manifest_stub:revert()
  end)

  --- Test: user can override default 'run' script
  it("allows user to override default 'run' script", function()
    local answers = { "Proj", "", "", "", "run", "custom run", "", "", "" }
    local saved_manifest
    local save_manifest_stub = stub(manifest_utils, "save_manifest", function(m)
      saved_manifest = m
      return true
    end)
    with_mocked_io_read(answers, function()
      init.init_project()
    end)
    assert.same(saved_manifest.scripts.run, "custom run")
    save_manifest_stub:revert()
  end)

  --- Test: no dependencies provided
  it("handles no dependencies", function()
    local answers = { "N", "", "", "", "", "", "", "" }
    local saved_manifest
    local save_manifest_stub = stub(manifest_utils, "save_manifest", function(m)
      saved_manifest = m
      return true
    end)
    with_mocked_io_read(answers, function()
      init.init_project()
    end)
    assert.same(saved_manifest.dependencies, {})
    save_manifest_stub:revert()
  end)

  --- Test: handles empty input for all prompts (uses defaults)
  it("uses defaults for empty input", function()
    local answers = { "", "", "", "", "", "", "", "" }
    local saved_manifest
    local save_manifest_stub = stub(manifest_utils, "save_manifest", function(m)
      saved_manifest = m
      return true
    end)
    with_mocked_io_read(answers, function()
      init.init_project()
    end)
    assert.same(saved_manifest.name, "my-lua-project")
    assert.same(saved_manifest.version, "0.0.1")
    assert.same(saved_manifest.license, "MIT")
    assert.same(saved_manifest.description, "A sample Lua project using Almandine.")
    save_manifest_stub:revert()
  end)

  --- Test: manifest_utils.save_manifest returns unexpected non-boolean
  it("handles manifest_utils returning non-boolean", function()
    local answers = { "A", "", "", "", "", "", "", "" }
    local save_manifest_stub = stub(manifest_utils, "save_manifest", function()
      return nil, "bad"
    end)
    local print_spy = spy.on(_G, "print")
    local exit_stub = stub(os, "exit", function(code)
      _G.exit_called = code
    end)
    with_mocked_io_read(answers, function()
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
end)
