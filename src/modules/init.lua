--- Init Module
--- Provides interactive project initialization and manifest creation.
--

---TODO: remove this once we have a pass over this file
--luacheck: ignore

-- Ensure relative paths work for requires within the project
local filesystem_utils = require("utils.filesystem")
package.path = filesystem_utils.join_path("src", "?.lua") .. ";" .. package.path
package.path = filesystem_utils.join_path("src", "lib", "?.lua") .. ";" .. package.path

---@class InitDeps
---@field prompt fun(msg: string, default: string|nil): string|nil Function to prompt user for input.
---@field println fun(...) Function to print output to the console.
---@field save_manifest fun(manifest: table): boolean, string? Function to save the manifest table.
---@field exit fun(code: number|nil) Function to exit the application.
---@field printer table Printer utility with stdout/stderr methods.

--- Internal helper function to prompt the user.
--- Uses the injected prompt function from dependencies.
---@param deps InitDeps The dependency table.
---@param msg string The prompt message.
---@param default string|nil The optional default value.
---@return string|nil The user's input or the default value.
local function _prompt_user(deps, msg, default)
  local formatted_msg = msg
  if default then
    formatted_msg = formatted_msg .. " [" .. default .. "]"
  end
  formatted_msg = formatted_msg .. ": "

  local input = deps.prompt(formatted_msg, default)

  -- Original logic retained: If input is empty string or nil, return default.
  -- Note: The injected prompt function might already handle the nil case depending on implementation.
  if input == "" or input == nil then
    return default
  else
    return input
  end
end

--- Prints usage/help information for the `init` command.
--- Usage: almd init
--- Initializes a new Almandine project interactively.
local function help_info()
  return [[
Usage: almd init

Interactively initializes a new Almandine project and creates a project.lua manifest.
]]
end

--- Initializes a new Almandine project by interactively prompting the user for manifest fields and writing project.lua.
---@param deps InitDeps Table containing dependency injected functions.
---@return boolean success True if successful, false otherwise.
---@return string|nil message Success message for stdout.
---@return string|nil error_message Error message for stderr.
function init_project(deps)
  deps.printer.stdout("Almandine Project Initialization")
  deps.printer.stdout("-------------------------------")
  local manifest = {}

  manifest.name = _prompt_user(deps, "Project name", "my-lua-project")
  manifest.type = "application" -- Defaulting for now, could prompt later
  manifest.version = _prompt_user(deps, "Project version", "0.0.1")
  manifest.license = _prompt_user(deps, "License", "MIT")
  manifest.description = _prompt_user(deps, "Description", "A sample Lua project using Almandine.")

  manifest.scripts = {}
  deps.println("Add scripts (leave name empty to finish):")
  while true do
    local script_name = _prompt_user(deps, "  Script name")
    if not script_name or script_name == "" then
      break
    end
    local script_cmd = _prompt_user(deps, "    Command for '" .. script_name .. "'")
    manifest.scripts[script_name] = script_cmd
  end
  -- Ensure a default 'run' script is present if not set
  if not manifest.scripts["run"] or manifest.scripts["run"] == "" then
    manifest.scripts["run"] = "lua src/main.lua"
    deps.println("Default 'run' script added: lua src/main.lua") -- Inform user
  end

  manifest.dependencies = {}
  deps.println("Add dependencies (leave name empty to finish):")
  while true do
    local dep_name = _prompt_user(deps, "  Dependency name")
    if not dep_name or dep_name == "" then
      break
    end
    local dep_ver = _prompt_user(deps, "    Version/source for '" .. dep_name .. "'")
    manifest.dependencies[dep_name] = dep_ver
  end

  local ok, err = deps.save_manifest(manifest)
  if not ok then
    return false, nil, "Error: Could not write project.lua - " .. tostring(err)
  end
  deps.println("\nproject.lua written successfully.")
  return true, "Project initialized successfully."
end

return {
  init_project = init_project,
  help_info = help_info,
}
