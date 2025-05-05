---
--- Main Entrypoint for Almandine Package Manager
---
--- This file serves as the main entrypoint for the Almandine Lua package manager.
--- It is responsible for bootstrapping the application and delegating control to the appropriate
--- modules based on user input or CLI arguments.
--- All initialization and top-level logic begins here.
---

---
-- Entry point for the Almandine CLI application.
-- Parses CLI arguments and dispatches to the appropriate command module.
---
-- @usage lua src/main.lua <command> [options]
--

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
local manifest_utils = require("utils.manifest")
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
  local manifest, err = manifest_utils.safe_load_project_manifest("project.lua")
  if not manifest then
    return nil, err
  end
  return manifest, nil
end

local function print_help()
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
 self uninstall        Remove the almd CLI
 self update           Update the almd CLI

Options:
-h, --help             Show this help message
-v, --version          Show version

For help with a command: almd help <command> or almd <command> --help
]]):format(version))
end

-- Helper to capture print_help output
local function get_help_string()
  local old_print = print
  local help_output = {}
  _G.print = function(...) -- Temporarily override print
    local parts = {}
    for i = 1, select("#", ...) do
      parts[i] = tostring(select(i, ...))
    end
    table.insert(help_output, table.concat(parts, "\t"))
  end
  print_help()
  _G.print = old_print -- Restore print
  return table.concat(help_output, "\n")
end

local function run_cli(args)
  ---
  -- Executes the appropriate Almandine command based on arguments.
  -- @return boolean success
  -- @return string message_or_error
  ---

  -- Helper function to get manifest, memoized per run_cli call
  local manifest_cache = nil
  local manifest_load_error = nil
  local function get_cached_manifest()
    if manifest_cache == nil and manifest_load_error == nil then
      manifest_cache, manifest_load_error = manifest_utils.safe_load_project_manifest("project.lua")
    end
    return manifest_cache, manifest_load_error
  end

  version_utils.check_lua_version(get_cached_manifest) -- Still check version early

  -- Handle no args or help flags
  if not args[1] or args[1] == "--help" or args[1] == "help" or (args[1] and args[1]:match("^%-h")) then
    return true, get_help_string() -- Use helper here
  end

  -- Handle version flag
  if args[1] == "-v" or args[1] == "--version" then
    local version = version_utils.get_version and version_utils.get_version() or "(unknown)"
    return true, "Almandine CLI v" .. version
  end

  -- Handle specific command help
  if args[1] == "help" or (args[2] and args[2] == "--help") then
    local cmd = args[2] or args[1] -- Command is the second arg if 'help' is first
    if args[1] == "help" and not args[2] then -- `almd help` case
      return true, get_help_string() -- Use helper here
    end

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
    if help_map[cmd] then
      -- Capture output of help function instead of printing directly
      local old_print = print
      local help_output = {}
      _G.print = function(...) -- Temporarily override print
        local parts = {}
        for i = 1, select("#", ...) do
          parts[i] = tostring(select(i, ...))
        end
        table.insert(help_output, table.concat(parts, "\t"))
      end
      help_map[cmd]()
      _G.print = old_print -- Restore print
      return true, table.concat(help_output, "\n")
    else
      return false, "Unknown command for help: " .. tostring(cmd)
    end
  end

  -- --- Command Execution ---
  local command = args[1]

  if command == "init" then
    -- Assuming init_project prints its own success/failure messages for now
    local ok, msg = init_module.init_project() -- TODO: Ensure init_project returns ok, msg
    return ok, msg or (ok and "Project initialized." or "Initialization failed.")
  elseif command == "add" then
    local source = args[2]
    if not source then
      return false, "Usage: almd add <source> [-d <dir>] [-n <dep_name>] [--verbose]"
    end

    local verbose = false
    local dest_dir, dep_name
    local i = 3
    while i <= #args do
      if args[i] == "-d" and args[i + 1] then
        dest_dir = args[i + 1]
        i = i + 2
      elseif args[i] == "-n" and args[i + 1] then
        dep_name = args[i + 1]
        i = i + 2
      elseif args[i] == "--verbose" then
        verbose = true
        i = i + 1
      else
        return false, "Unknown or incomplete flag: " .. tostring(args[i])
      end
    end

    local ok, fatal_err, warning_occurred, warning_msg = add_module.add_dependency(dep_name, source, dest_dir, {
      load_manifest = manifest_utils.safe_load_project_manifest,
      save_manifest = manifest_utils.save_manifest,
      ensure_lib_dir = filesystem_utils.ensure_lib_dir,
      downloader = downloader,
      hash_utils = require("utils.hash"),
      lockfile = require("utils.lockfile"),
      verbose = verbose,
    })

    local final_message = ""
    if warning_occurred then
      final_message = "Warning(s): " .. (warning_msg or "Unknown warning") .. "\n"
    end

    if not ok then
      final_message = final_message .. "Error: Add operation failed.\n"
      if fatal_err then
        final_message = final_message .. "  Reason: " .. fatal_err
      end
      return false, final_message:gsub("\n$", "") -- Trim trailing newline
    else
      -- Optionally add a success message part
      return true, final_message .. "Dependency added successfully."
    end

  elseif command == "install" or command == "i" then
    local dep_name = args[2]
    local deps = {
      load_manifest = get_cached_manifest,
      ensure_lib_dir = filesystem_utils.ensure_lib_dir,
      downloader = downloader,
      lockfile = require("utils.lockfile"),
      hash_utils = require("utils.hash"),
      filesystem = filesystem_utils,
      url_utils = require("utils.url"),
    }
    local ok, msg = install_module.install_dependencies(dep_name, deps)
    if not ok then
      return false, "Installation failed: " .. tostring(msg or "Unknown error")
    end
    return true, msg or "Installation complete."

  elseif command == "remove" or command == "rm" or command == "uninstall" or command == "un" then
    local dep_name = args[2]
    if not dep_name then
      return false, "Usage: almd remove <dep_name>"
    end
    local ok, msg = remove_module.remove_dependency(
      dep_name,
      get_cached_manifest,
      manifest_utils.save_manifest
    )
    if not ok then
      return false, msg or "Removal failed."
    end
    return true, msg or "Dependency removed."

  elseif command == "update" or command == "up" then
    local latest = false
    for i = 2, #args do
      if args[i] == "--latest" then
        latest = true
      end
    end
    update_module.update_dependencies(
      get_cached_manifest,
      manifest_utils.save_manifest,
      filesystem_utils.ensure_lib_dir,
      { downloader = downloader },
      add_module.resolve_latest_version,
      latest
    )
    return true, "Update process initiated. Check output for details." -- Placeholder message

  elseif command == "run" then
    local script_name = args[2]
    if not script_name then
      return false, "Usage: almd run <script_name>"
    end
    local deps = { manifest_loader = get_cached_manifest }
    local ok, msg = run_module.run_script(script_name, deps)
    if not ok then
      return false, msg -- run_script returns the error message
    end
    return true, msg or ("Script '" .. script_name .. "' executed.") -- Return output or basic success

  elseif command == "list" or command == "ls" then
    local old_print = print
    local list_output = {}
    _G.print = function(...) -- Temporarily override print
      local parts = {}
      for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
      end
      table.insert(list_output, table.concat(parts, "\t"))
    end
    list_module.list_dependencies(get_cached_manifest)
    _G.print = old_print -- Restore print
    return true, table.concat(list_output, "\n")

  elseif command == "self" and args[2] == "uninstall" then
    local ok, err = self_module.uninstall_self()
    if ok then
      return true, "almd self uninstall: Success."
    else
      return false, "almd self uninstall: Failed.\n" .. (err or "Unknown error.")
    end
  elseif command == "self" and args[2] == "update" then
    local ok, msg = self_module.self_update()
    if ok then
      return true, "almd self update: Success."
    elseif msg == "Update staged for next run." then
      return true, msg -- Special case, considered success
    else
      return false, "almd self update: Failed.\n" .. (msg or "Unknown error.")
    end

  elseif not run_module.is_reserved_command(command) then
    -- Check for unambiguous script name if not a reserved command
    local deps = { manifest_loader = get_cached_manifest }
    local script_name = run_module.get_unambiguous_script(command, deps)
    if script_name then
      local ok, msg = run_module.run_script(script_name, deps)
      if not ok then
        return false, msg
      end
      return true, msg or ("Script '" .. script_name .. "' executed.")
    end
  end

  -- If command wasn't handled, return generic help/error
  return false, "Unknown command or usage error: '" .. tostring(command) .. "'\\n\\n" .. get_help_string() -- Use helper here
end

-- Wrapper for run_cli to handle exit code
local function main(...)
  local ok, message = run_cli({ ... })

  if message then
    print(message)
  end

  if not ok then
    os.exit(1)
  end
end

-- Entry point check: only run main if script is executed directly
if not pcall(debug.getlocal, 2, 1) then
  main(unpack(arg, 1))
end

-- Export the run_cli function for testing or programmatic use
return {
  run_cli = run_cli,
}
