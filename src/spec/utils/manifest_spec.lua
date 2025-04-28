--[[
  Spec: Manifest Loader Utility

  Tests for src/utils/manifest.lua covering all code paths in manifest.safe_load_project_manifest.
]]
--

local manifest = require("utils.manifest")
local tmpfile = "_almd_test_project.lua"

local function write_file(path, content)
  local f = assert(io.open(path, "w"))
  f:write(content)
  f:flush() -- ensure content is written to disk
  f:close()
end

local function remove_file(path)
  os.remove(path)
end

describe("manifest.safe_load_project_manifest", function()
  after_each(function()
    remove_file(tmpfile)
  end)

  it("loads a valid manifest table", function()
    write_file(tmpfile, "return { name = 'test' }")
    local tbl, err = manifest.safe_load_project_manifest(tmpfile)
    assert.is_table(tbl)
    assert.are.equal(tbl.name, "test")
    assert.is_nil(err)
  end)

  it("returns error if file does not exist", function()
    local tbl, err = manifest.safe_load_project_manifest("nonexistent_file.lua")
    assert.is_nil(tbl)
    assert.is_not_nil(err)
    assert.is_string(err)
    assert.is_not_nil(err:find("No such file") or err:find("cannot open"))
  end)

  it("returns error if file has syntax error", function()
    write_file(tmpfile, "return { name = 'test', } thisisnotlua")
    local tbl, err = manifest.safe_load_project_manifest(tmpfile)
    if err == nil then
      print("DEBUG: err is nil for syntax error case!")
    else
      print("DEBUG: err for syntax error case:", err)
    end
    assert.is_nil(tbl)
    assert.is_not_nil(err)
    assert.is_string(err)
    assert.is_true(#err > 0)
  end)

  it("returns error if file throws at runtime", function()
    write_file(tmpfile, "error('fail on load')")
    local tbl, err = manifest.safe_load_project_manifest(tmpfile)
    assert.is_nil(tbl)
    assert.is_not_nil(err)
    assert.is_string(err)
    assert.is_not_nil(err:find("fail on load"))
  end)

  it("returns error if manifest does not return a table", function()
    write_file(tmpfile, "return 42")
    local tbl, err = manifest.safe_load_project_manifest(tmpfile)
    assert.is_nil(tbl)
    assert.is_not_nil(err)
    assert.is_string(err)
    assert.are.equal(err, "Manifest must return a table")
  end)
end)
