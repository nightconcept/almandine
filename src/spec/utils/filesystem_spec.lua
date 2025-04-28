--[[
  Spec: Filesystem Utilities

  Tests for src/utils/filesystem.lua covering directory creation and path joining.
]]--

local filesystem = require("utils.filesystem")

-- Helper to detect OS for path separator
local sep = package.config:sub(1, 1)

-- Test suite for join_path
describe("filesystem.join_path", function()
  it("joins two segments", function()
    assert.are.equal("foo" .. sep .. "bar", filesystem.join_path("foo", "bar"))
  end)

  it("joins multiple segments", function()
    assert.are.equal("foo" .. sep .. "bar" .. sep .. "baz", filesystem.join_path("foo", "bar", "baz"))
  end)

  it("returns single segment as-is", function()
    assert.are.equal("foo", filesystem.join_path("foo"))
  end)
end)

describe("filesystem.ensure_lib_dir", function()
  it("calls os.execute with correct mkdir on unix", function()
    local called = false
    local test_sep = "/"
    local function fake_execute(cmd)
      called = cmd
      return 0
    end
    filesystem.ensure_lib_dir(test_sep, fake_execute)
    assert.is_true(type(called) == "string" and called:match("mkdir %-p src/lib"))
  end)

  it("calls os.execute with correct mkdir on windows", function()
    local called = false
    local test_sep = "\\"
    local function fake_execute(cmd)
      called = cmd
      return 0
    end
    filesystem.ensure_lib_dir(test_sep, fake_execute)
    assert.is_true(type(called) == "string" and called:match("mkdir src\\lib"))
  end)
end)
