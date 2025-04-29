--[[
  Init Module

  This module implements interactive project initialization, manifest creation, and related helpers.
]]
--

-- Add both src/ and src/lib/ to package.path for require
local src_path = "src/?.lua"
local lib_path = "src/lib/?.lua"
if not string.find(package.path, src_path, 1, true) then
  package.path = src_path .. ";" .. package.path
end
if not string.find(package.path, lib_path, 1, true) then
  package.path = lib_path .. ";" .. package.path
end

local M = {}

--- Prompts the user for input with an optional default value.
-- @param msg string The prompt message.
-- @param default string The default value.
-- @return string The user's input or the default value if empty.
local function prompt(msg, default)
  io.write(msg)
  if default then
    io.write(" [" .. default .. "]")
  end
  io.write(": ")
  local input = io.read()
  if input == "" or input == nil then
    return default
  else
    return input
  end
end

local manifest_utils = require("utils.manifest")

--- Prints usage/help information for the `init` command.
-- Usage: almd init
-- Initializes a new Almandine project interactively.
local function help_info()
  print([[\nUsage: almd init

Interactively initializes a new Almandine project and creates a project.lua manifest.
]])
end

--- Initializes a new Almandine project by interactively prompting the user for manifest fields and writing project.lua.
function M.init_project()
  print("Almandine Project Initialization\n-------------------------------")
  local manifest = {}
  manifest.name = prompt("Project name", "my-lua-project")
  manifest.type = "application"
  manifest.version = prompt("Project version", "0.0.1")
  manifest.license = prompt("License", "MIT")
  manifest.description = prompt("Description", "A sample Lua project using Almandine.")

  -- Scripts
  manifest.scripts = {}
  print("Add scripts (leave name empty to finish):")
  while true do
    local script_name = prompt("  Script name")
    if not script_name or script_name == "" then
      break
    end
    local script_cmd = prompt("    Command for '" .. script_name .. "'")
    manifest.scripts[script_name] = script_cmd
  end
  -- Ensure a default 'run' script is present if not set
  manifest.scripts["run"] = "lua src/main.lua"

  -- Dependencies
  manifest.dependencies = {}
  print("Add dependencies (leave name empty to finish):")
  while true do
    local dep_name = prompt("  Dependency name")
    if not dep_name or dep_name == "" then
      break
    end
    local dep_ver = prompt("    Version/source for '" .. dep_name .. "'")
    manifest.dependencies[dep_name] = dep_ver
  end

  -- Write manifest to project.lua
  local ok, err = manifest_utils.save_manifest(manifest)
  if not ok then
    print("Error: Could not write project.lua - " .. tostring(err))
    os.exit(1)
  end
  print("\nproject.lua written successfully.")
end

M.help_info = help_info

return M
