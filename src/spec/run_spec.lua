--[[
  Run Command Specification

  Busted test suite for the run command module in src/modules/run.lua.
  - Verifies script running, error handling, reserved command detection, and script resolution.
]]
--

-- luacheck: globals describe it assert

--- Run module specification for Busted.
-- @module run_spec

describe("run_module", function()
  local run_module = require("modules.run")
  local _manifest_loader = require("utils.manifest")
  local _ = _manifest_loader

  local function fake_manifest_loader(scripts)
    return {
      safe_load_project_manifest = function()
        return { scripts = scripts }, nil
      end,
    }
  end

  it("runs a script successfully", function()
    local scripts = { hello = "echo hello world" }
    local loader = fake_manifest_loader(scripts)
    local ok, _ = run_module.run_script("hello", loader)
    assert.is_true(ok)
  end)

  it("returns error if script not found", function()
    local scripts = { hello = "echo hello world" }
    local loader = fake_manifest_loader(scripts)
    local ok, _ = run_module.run_script("nonexistent_script", loader)
    assert.is_false(ok)
    assert.matches("not found", _)
  end)

  it("detects reserved commands", function()
    assert.is_true(run_module.is_reserved_command("init"))
    assert.is_false(run_module.is_reserved_command("hello"))
  end)

  it("resolves unambiguous script", function()
    local scripts = { foo = "echo foo", bar = "echo bar" }
    local loader = fake_manifest_loader(scripts)
    assert.are.equal(run_module.get_unambiguous_script("foo", loader), "foo")
    assert.is_nil(run_module.get_unambiguous_script("baz", loader))
  end)
end)
