--[[
Dummy Spec

Tests dummy.lua
]]
--

--- Add module specification for Busted.
-- @module dummy_spec

describe("dummy", function()
  it("should always pass", function()
    assert.is_true(true)
  end)

  it("should do basic math correctly", function()
    assert.equals(2 + 2, 4)
  end)
end)
