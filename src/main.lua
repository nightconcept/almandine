--[[
  Main Entrypoint for Almandine Package Manager

  This file serves as the main entrypoint for the Almandine Lua package manager. It is responsible for bootstrapping the application and delegating control to the appropriate modules based on user input or CLI arguments. All initialization and top-level logic begins here.
]]--

---
-- Entry point for the Almandine CLI application.
-- Parses CLI arguments and dispatches to the appropriate command module.
--
-- @usage lua src/main.lua <command> [options]
--
-- @class MainEntrypoint

-- Add both src/ and src/lib/ to package.path for require
local src_path = "src/?.lua"
local lib_path = "src/lib/?.lua"
if not string.find(package.path, src_path, 1, true) then
  package.path = src_path .. ";" .. package.path
end
if not string.find(package.path, lib_path, 1, true) then
  package.path = lib_path .. ";" .. package.path
end

local downloader = require("utils.downloader")
local manifest_loader = require("utils.manifest")
local init_module = require("modules.init")
local add_module = require("modules.add")
local install_module = require("modules.install")
local remove_module = require("modules.remove")
local filesystem_utils = require("utils.filesystem")
local version_utils = require("utils.version")
local update_module = require("modules.update")

local function load_manifest()
  local manifest, err = manifest_loader.safe_load_project_manifest("project.lua")
  if not manifest then return nil, err end
  return manifest, nil
end

local function main(...)
  --- The main entry point for the Almandine CLI application.
  --
  -- @param ... string CLI arguments.
  version_utils.check_lua_version(load_manifest)
  local args = {...}
  if args[1] == "init" then
    init_module.init_project()
    return
  elseif args[1] == "add" or args[1] == "i" then
    -- Usage: almandine add <dep_name> <source>
    if args[2] and args[3] then
      add_module.add_dependency(args[2], args[3], load_manifest, install_module.save_manifest or save_manifest, filesystem_utils.ensure_lib_dir, downloader)
    else
      print("Usage: almandine add <dep_name> <source>")
    end
    return
  elseif args[1] == "install" or args[1] == "in" or args[1] == "ins" then
    -- Usage: almandine install [<dep_name>]
    if args[2] then
      install_module.install_dependencies(args[2], load_manifest, filesystem_utils.ensure_lib_dir, downloader)
    else
      install_module.install_dependencies(nil, load_manifest, filesystem_utils.ensure_lib_dir, downloader)
    end
    return
  elseif args[1] == "remove" or args[1] == "rm" or args[1] == "uninstall" or args[1] == "un" then
    if args[2] then
      remove_module.remove_dependency(args[2], load_manifest, install_module.save_manifest or save_manifest)
    else
      print("Usage: almandine remove <dep_name>")
    end
    return
  elseif args[1] == "update" or args[1] == "up" or args[1] == "upgrade" then
    -- Usage: almandine update [--latest]
    local latest = false
    for i = 2, #args do
      if args[i] == "--latest" then
        latest = true
      end
    end
    update_module.update_dependencies(
      load_manifest,
      install_module.save_manifest or save_manifest,
      filesystem_utils.ensure_lib_dir,
      {downloader = downloader},
      add_module.resolve_latest_version,
      latest
    )
    return
  elseif args[1] == "run" then
    if not args[2] then
      print("Usage: almandine run <script_name>")
      return
    end
    local script_name = args[2]
    local manifest, err = load_manifest()
    if not manifest then
      print(err)
      return
    end
    local scripts = manifest.scripts or {}
    local command = scripts[script_name]
    if not command then
      print(string.format("Script '%s' not found in project.lua.", script_name))
      return
    end
    print(string.format("Running script '%s': %s", script_name, command))
    local ok, exit_reason, code = os.execute(command)
    if ok then
      print(string.format("Script '%s' completed successfully.", script_name))
    else
      print(string.format("Script '%s' failed (reason: %s, code: %s)", script_name, tostring(exit_reason), tostring(code)))
    end
    return
  end
  print("Almandine Package Manager: main entrypoint initialized.")
  -- TODO: Parse CLI arguments and dispatch to subcommands/modules
end

-- Expose install_dependencies and remove_dependency for testing
return {
  install_dependencies = install_module.install_dependencies,
  remove_dependency = remove_module.remove_dependency,
  main = main
}
