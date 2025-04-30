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
    local deps = { manifest_loader = fake_manifest_loader(scripts) }
    local ok, _ = run_module.run_script("hello", deps)
    assert.is_true(ok)
  end)

  it("returns error if script not found", function()
    local scripts = { hello = "echo hello world" }
    local deps = { manifest_loader = fake_manifest_loader(scripts) }
    local ok, _ = run_module.run_script("nonexistent_script", deps)
    assert.is_false(ok)
    assert.matches("not found", _)
  end)

  it("detects reserved commands", function()
    assert.is_true(run_module.is_reserved_command("init"))
    assert.is_false(run_module.is_reserved_command("hello"))
  end)

  it("resolves unambiguous script", function()
    local scripts = { foo = "echo foo", bar = "echo bar" }
    local deps = { manifest_loader = fake_manifest_loader(scripts) }
    assert.are.equal(run_module.get_unambiguous_script("foo", deps), "foo")
    assert.is_nil(run_module.get_unambiguous_script("baz", deps))
  end)

  it("returns error if manifest fails to load", function()
    local deps = {
      manifest_loader = {
        safe_load_project_manifest = function()
          return nil
        end,
      },
    }
    local ok, err = run_module.run_script("hello", deps)
    assert.is_false(ok)
    assert.matches("Failed to load project manifest", err)
  end)

  it("runs a script with cmd and args table", function()
    local scripts = {
      hello = { cmd = "echo", args = { "hello", "world" } },
    }
    local deps = { manifest_loader = fake_manifest_loader(scripts) }
    local ok, _ = run_module.run_script("hello", deps)
    assert.is_true(ok)
  end)

  it("handles script execution failure", function()
    local scripts = { fail = "failing_cmd" }
    local fake_executor = function()
      return false, "exit", 1
    end
    local deps = {
      manifest_loader = fake_manifest_loader(scripts),
      executor = fake_executor,
    }
    local ok, err = run_module.run_script("fail", deps)
    assert.is_false(ok)
    assert.matches("failed", err)
  end)

  it("handles empty scripts table", function()
    local deps = { manifest_loader = fake_manifest_loader({}) }
    local ok, err = run_module.run_script("anything", deps)
    assert.is_false(ok)
    assert.matches("not found", err)
  end)

  it("prints help info", function()
    assert.has_no.errors(run_module.help_info)
  end)
end)
