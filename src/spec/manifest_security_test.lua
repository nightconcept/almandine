--[[
  Security tests for project.lua manifest loading
  Ensures that unsafe code in project.lua is rejected by the loader.
]]--

-- Use the manifest_loader module directly for testing
local manifest_loader = require("src.lib.manifest_loader")

local function write_file(path, content)
  local f = assert(io.open(path, "w"))
  f:write(content)
  f:close()
end

local function cleanup(path)
  os.remove(path)
end

local function test_safe_manifest()
  local good = [[return {
    name = "ok",
    dependencies = {}
  }]]
  write_file("project.lua", good)
  local manifest, err = manifest_loader.safe_load_project_manifest("project.lua")
  assert(manifest and manifest.name == "ok", "Safe manifest should load: " .. tostring(err))
  cleanup("project.lua")
end

local function test_unsafe_manifest()
  local bads = {
    -- Function call
    "return (function() os.execute('rm -rf /') end)()",
    -- Function definition
    "return { f = function() end }",
    -- Assignment
    "x = 1\nreturn {}",
    -- Control flow
    "if true then return {} end",
    -- Table with metatable
    "return setmetatable({}, {})"
  }
  for i, bad in ipairs(bads) do
    write_file("project.lua", bad)
    local manifest, err = manifest_loader.safe_load_project_manifest("project.lua")
    assert(not manifest and err, "Unsafe manifest #"..i.." should be rejected")
    cleanup("project.lua")
  end
end

print("[SECURITY TEST] Testing safe manifest...")
test_safe_manifest()
print("[SECURITY TEST] Testing unsafe manifests...")
test_unsafe_manifest()
print("[SECURITY TEST] All security checks passed.")
