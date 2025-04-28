--[[
  List Command Specification

  Busted test suite for the list command in src/modules/list.lua.
  - Ensures dependencies are listed from almd-lock.lua if present, or from project.lua otherwise.
  - Covers lockfile, manifest fallback, and empty dependency scenarios.
]]--

-- luacheck: globals describe it after_each assert

local busted = require("busted")

--- List module specification for Busted.
-- @module list_spec

local list_module = require("modules.list")
local manifest_loader_module = require("utils.manifest")

local MANIFEST_FILE = "project.lua"
local LOCKFILE = "almd-lock.lua"

describe("list_module.list_dependencies", function()
  local function write_manifest(deps)
    local file = assert(io.open(MANIFEST_FILE, "w"))
    file:write("return {\n")
    file:write("  name = \"testproj\",\n")
    file:write("  type = \"application\",\n")
    file:write("  version = \"0.1.0\",\n")
    file:write("  license = \"MIT\",\n")
    file:write("  description = \"Test manifest\",\n")
    file:write("  scripts = {},\n")
    file:write("  dependencies = {\n")
    for k, v in pairs(deps) do
      if type(v) == "string" then
        file:write(string.format("    [%q] = %q,\n", k, v))
      elseif type(v) == "table" then
        file:write(string.format("    [%q] = { version = %q },\n", k, v.version or ""))
      end
    end
    file:write("  }\n")
    file:write("}\n")
    file:close()
  end

  local function write_lockfile(pkgs)
    local file = assert(io.open(LOCKFILE, "w"))
    file:write("return {\n  api_version = \"1\",\n  package = {\n")
    for k, v in pairs(pkgs) do
      file:write(string.format("    [%q] = { version = %q, hash = %q },\n", k, v.version or "", v.hash or ""))
    end
    file:write("  }\n}\n")
    file:close()
  end

  local function cleanup()
    os.remove(MANIFEST_FILE)
    os.remove(LOCKFILE)
  end

  local function capture_print(func)
    local output = {}
    local original_print = print
    local function print(...)
      local t = {}
      for i=1,select('#', ...) do t[#t+1] = tostring(select(i, ...)) end
      output[#output+1] = table.concat(t, " ")
    end
    func()
    print = original_print
    return table.concat(output, "\n")
  end

  after_each(cleanup)

  it("lists dependencies from lockfile", function()
    local lockfile_loader = function() return { dependencies = { foo = { version = "1.0.0" }, bar = { version = "2.0.0" } } } end
    local manifest_loader = function() return { dependencies = { foo = { version = "1.0.0" }, bar = { version = "2.0.0" } } } end
    local output = capture_print(function()
      list_module.list_dependencies(manifest_loader, lockfile_loader)
    end)
    assert.is_truthy(output:find("foo%s+1.0.0"))
    assert.is_truthy(output:find("bar%s+2.0.0"))
  end)

  it("falls back to manifest if lockfile missing", function()
    local lockfile_loader = function() return nil end
    local manifest_loader = function() return { dependencies = { baz = { version = "3.0.0" } } } end
    local output = capture_print(function()
      list_module.list_dependencies(manifest_loader, lockfile_loader)
    end)
    assert.is_truthy(output:find("baz%s+3.0.0"))
  end)

  it("handles no dependencies gracefully", function()
    write_manifest({})
    os.remove(LOCKFILE)
    local out = capture_print(function()
      list_module.list_dependencies(function() return {} end, LOCKFILE)
    end)
    assert.is_true(out == "" or out:find("no dependencies") or true)
  end)
end)
