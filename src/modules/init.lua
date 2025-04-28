--[[
  Project Initialization Module for Snowdrop

  This module implements interactive project initialization, manifest creation, and related helpers.
]]--

-- Add both src/ and src/lib/ to package.path for require
local src_path = "src/?.lua"
local lib_path = "src/lib/?.lua"
if not string.find(package.path, src_path, 1, true) then
  package.path = src_path .. ";" .. package.path
end
if not string.find(package.path, lib_path, 1, true) then
  package.path = lib_path .. ";" .. package.path
end

local manifest_loader = require("manifest_loader")

local M = {}

--- Prompts the user for input with an optional default value.
-- @param msg string The prompt message.
-- @param default string The default value.
-- @return string The user's input or the default value if empty.
local function prompt(msg, default)
  io.write(msg)
  if default then io.write(" [" .. default .. "]") end
  io.write(": ")
  local input = io.read()
  if input == "" or input == nil then return default else return input end
end

--- Saves the project manifest to project.lua.
-- @param manifest table Manifest table to save.
-- @return boolean, string True on success, false and error message on failure.
local function save_manifest(manifest)
  local file, err = io.open("project.lua", "w")
  if not file then return false, "Could not write project.lua: " .. tostring(err) end
  file:write("return {\n")
  file:write(string.format("  name = \"%s\",\n", manifest.name or ""))
  file:write(string.format("  type = \"%s\",\n", manifest.type or ""))
  file:write(string.format("  version = \"%s\",\n", manifest.version or ""))
  file:write(string.format("  license = \"%s\",\n", manifest.license or ""))
  file:write(string.format("  description = \"%s\",\n", manifest.description or ""))
  file:write("  scripts = {\n")
  for k, v in pairs(manifest.scripts or {}) do
    file:write(string.format("    %s = \"%s\",\n", k, v))
  end
  file:write("  },\n  dependencies = {\n")
  for k, v in pairs(manifest.dependencies or {}) do
    file:write(string.format("    [%q] = \"%s\",\n", k, v))
  end
  file:write("  }\n}\n")
  file:close()
  return true, nil
end

--- Initializes a new Snowdrop project by interactively prompting the user for manifest fields and writing project.lua.
function M.init_project()
  print("Snowdrop Project Initialization\n-------------------------------")
  local manifest = {}
  manifest.name = prompt("Project name", "my-lua-project")
  manifest.type = "application"
  manifest.version = prompt("Project version", "0.0.1")
  manifest.license = prompt("License", "MIT")
  manifest.description = prompt("Description", "A sample Lua project using Snowdrop.")

  -- Scripts
  manifest.scripts = {}
  print("Add scripts (leave name empty to finish):")
  while true do
    local script_name = prompt("  Script name")
    if not script_name or script_name == "" then break end
    local script_cmd = prompt("    Command for '" .. script_name .. "'")
    manifest.scripts[script_name] = script_cmd
  end

  -- Dependencies
  manifest.dependencies = {}
  print("Add dependencies (leave name empty to finish):")
  while true do
    local dep_name = prompt("  Dependency name")
    if not dep_name or dep_name == "" then break end
    local dep_ver = prompt("    Version/source for '" .. dep_name .. "'")
    manifest.dependencies[dep_name] = dep_ver
  end

  -- Write manifest to project.lua
  local ok, err = save_manifest(manifest)
  if not ok then
    print("Error: Could not write project.lua - " .. tostring(err))
    os.exit(1)
  end
  print("\nproject.lua written successfully.")
end

return M
