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

local unpack = table.unpack or unpack

local downloader = require("utils.downloader")
local manifest_loader = require("utils.manifest")
local init_module = require("modules.init")
local add_module = require("modules.add")
local install_module = require("modules.install")
local remove_module = require("modules.remove")
local filesystem_utils = require("utils.filesystem")
local version_utils = require("utils.version")
local update_module = require("modules.update")
local run_module = require("modules.run")
local list_module = require("modules.list")
local self_module = require("modules.self")

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
      add_module.add_dependency(args[2], args[3], load_manifest, install_module.save_manifest, filesystem_utils.ensure_lib_dir, downloader)
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
      remove_module.remove_dependency(args[2], load_manifest, install_module.save_manifest)
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
      install_module.save_manifest,
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
    local ok, err = run_module.run_script(args[2], manifest_loader)
    if not ok then
      print(err)
    end
    return
  elseif args[1] == "list" then
    list_module.list_dependencies(load_manifest)
    return
  elseif args[1] == "self" and args[2] == "uninstall" then
    local ok, err = self_module.uninstall_self()
    if ok then
      print("almd self uninstall: Success. Wrapper scripts and src/ folder removed.")
    else
      print("almd self uninstall: Failed.\n" .. (err or "Unknown error."))
    end
    return
  elseif not run_module.is_reserved_command(args[1]) then
    -- If not a reserved command, check if it's an unambiguous script name
    local script_name = run_module.get_unambiguous_script(args[1], manifest_loader)
    if script_name then
      local ok, err = run_module.run_script(script_name, manifest_loader)
      if not ok then
        print(err)
      end
      return
    end
  end
  print("Almandine Package Manager: main entrypoint initialized.")
  -- TODO: Parse CLI arguments and dispatch to subcommands/modules
end

main(unpack(arg, 1))

return {
  remove_dependency = remove_module.remove_dependency
}
