--[[
  Main Entrypoint for Almandine Package Manager

  This file serves as the main entrypoint for the Almandine Lua package manager.
  It is responsible for bootstrapping the application and delegating control to the appropriate
  modules based on user input or CLI arguments.
  All initialization and top-level logic begins here.
]]
--

---
-- Entry point for the Almandine CLI application.
-- Parses CLI arguments and dispatches to the appropriate command module.
--
-- @usage lua src/main.lua <command> [options]
--
-- @class MainEntrypoint

-- Robustly set package.path relative to this script's directory (cross-platform)
local function script_dir()
  local info = debug.getinfo(1, "S").source
  local path = info:sub(1, 1) == "@" and info:sub(2) or info
  -- Normalize path separators for Windows
  path = path:gsub("\\", "/")
  return path:match("(.*/)") or "./"
end

local dir = script_dir()
if not package.path:find(dir .. "?.lua", 1, true) then
  package.path = dir .. "?.lua;" .. package.path
end
if not package.path:find(dir .. "?/init.lua", 1, true) then
  package.path = dir .. "?/init.lua;" .. package.path
end
if not package.path:find(dir .. "lib/?.lua", 1, true) then
  package.path = dir .. "lib/?.lua;" .. package.path
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
  if not manifest then
    return nil, err
  end
  return manifest, nil
end

local function main(...)
  --- The main entry point for the Almandine CLI application.
  --
  -- @param ... string CLI arguments.
  version_utils.check_lua_version(load_manifest)
  local args = { ... }
  -- pnpm-style usage/help if no arguments
  if not args[1] or args[1] == "--help" or args[1] == "help" or (args[2] and args[2] == "--help") then
    local version = version_utils.get_version and version_utils.get_version() or "(unknown)"
    print(([[
Almandine CLI v%s

Usage: almd [command] [options]
       almd [ -h | --help | -v | --version ]

Project Management:
   init                  Initialize a new Lua project in the current directory

Dependency Management:
   add                   Add a dependency to the project
   install               Install all dependencies listed in project.lua (aliases: i)
   remove                Remove a dependency from the project (aliases: rm, uninstall, un)
   update                Update dependencies to latest allowed version (aliases: up)
   list                  List installed dependencies and their versions (aliases: ls)

Scripts:
   run                   Run a script defined in project.lua scripts table

Self-management:
   self uninstall        Remove the almd CLI and wrapper scripts

Options:
  -h, --help             Show this help message
  -v, --version          Show version

For help with a command: almd help <command> or almd <command> --help
]]):format(version))
    return
  end
  -- Modular help delegation
  if args[1] == "--help" or args[1] == "help" or (args[2] and args[2] == "--help") then
    local cmd = args[2] or args[1]
    local help_map = {
      init = init_module.help_info,
      add = add_module.help_info,
      install = install_module.help_info,
      remove = remove_module.help_info,
      update = update_module.help_info,
      run = run_module.help_info,
      list = list_module.help_info,
      ["self"] = self_module.help_info,
    }
    if not args[2] or args[1] == "--help" then
      print([[almd: Modern Lua Package Manager

Usage: almd <command> [options]

Commands:
  init       Initialize a new Lua project
  add        Add a dependency to the project
  install    Install dependencies
  remove     Remove a dependency
  update     Update dependencies
  run        Run a project script
  list       List installed dependencies
  self       Self-management commands

For help with a command: almd help <command> or almd <command> --help
]])
      return
    elseif help_map[cmd] then
      help_map[cmd]()
      return
    else
      print("Unknown command for help: " .. tostring(cmd))
      return
    end
  end
  if args[1] == "init" then
    init_module.init_project()
    return
  elseif args[1] == "add" then
    -- Usage: almd add <dep_name> <source> OR almd add <source>
    if args[2] and args[3] then
      add_module.add_dependency(
        args[2],
        args[3],
        load_manifest,
        install_module.save_manifest,
        filesystem_utils.ensure_lib_dir,
        downloader
      )
    elseif args[2] and not args[3] then
      -- Only one argument: treat as source, dep_name=nil
      add_module.add_dependency(
        nil,
        args[2],
        load_manifest,
        install_module.save_manifest,
        filesystem_utils.ensure_lib_dir,
        downloader
      )
    else
      print("Usage: almd add <dep_name> <source>\n       almd add <source>")
    end
    return
  elseif args[1] == "install" or args[1] == "i" then
    -- Usage: almd install [<dep_name>]
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
      print("Usage: almd remove <dep_name>")
    end
    return
  elseif args[1] == "update" or args[1] == "up" then
    -- Usage: almd update [--latest]
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
      { downloader = downloader },
      add_module.resolve_latest_version,
      latest
    )
    return
  elseif args[1] == "run" then
    if not args[2] then
      print("Usage: almd run <script_name>")
      return
    end
    local ok, err = run_module.run_script(args[2], manifest_loader)
    if not ok then
      print(err)
    end
    return
  elseif args[1] == "list" or args[1] == "ls" then
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
  remove_dependency = remove_module.remove_dependency,
}
