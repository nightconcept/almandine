--[[
  Specification for src/utils/version.lua

  Ensures all public API and edge cases of version utilities are covered.
]]
--

local version = require("utils.version")

describe("utils.version", function()
  describe("parse_lua_version", function()
    it("parses major, minor, patch", function()
      local maj, min, pat = version.parse_lua_version("5.1.4")
      assert.are.same({ 5, 1, 4 }, { maj, min, pat })
    end)
    it("parses major, minor only", function()
      local maj, min, pat = version.parse_lua_version("5.2")
      assert.are.same({ 5, 2, 0 }, { maj, min, pat })
    end)
  end)

  describe("compare_lua_versions", function()
    it("returns 0 if equal", function()
      assert.are.equal(0, version.compare_lua_versions({ 5, 1, 4 }, { 5, 1, 4 }))
    end)
    it("returns negative if a < b", function()
      assert.is_true(version.compare_lua_versions({ 5, 1, 3 }, { 5, 1, 4 }) < 0)
      assert.is_true(version.compare_lua_versions({ 5, 0, 9 }, { 5, 1, 0 }) < 0)
    end)
    it("returns positive if a > b", function()
      assert.is_true(version.compare_lua_versions({ 5, 2, 0 }, { 5, 1, 9 }) > 0)
      assert.is_true(version.compare_lua_versions({ 6, 0, 0 }, { 5, 4, 9 }) > 0)
    end)
    it("handles missing patch", function()
      assert.are.equal(0, version.compare_lua_versions({ 5, 1 }, { 5, 1, 0 }))
      assert.is_true(version.compare_lua_versions({ 5, 1, 1 }, { 5, 1 }) > 0)
    end)
  end)

  describe("lua_version_satisfies", function()
    it("returns true for empty or nil", function()
      assert.is_true(version.lua_version_satisfies(nil))
      assert.is_true(version.lua_version_satisfies(""))
    end)
  end)

  describe("get_version", function()
    it("returns version string if almd_version returns string", function()
      package.loaded["almd_version"] = "1.2.3"
      assert.are.equal("1.2.3", version.get_version())
    end)
    it("returns (unknown) if require fails", function()
      package.loaded["almd_version"] = nil
      local orig_pcall = pcall
      _G.pcall = function()
        return false
      end
      assert.are.equal("(unknown)", version.get_version())
      _G.pcall = orig_pcall
    end)
    it("returns (unknown) if require does not return string", function()
      package.loaded["almd_version"] = 123
      assert.are.equal("(unknown)", version.get_version())
    end)
  end)
end)
