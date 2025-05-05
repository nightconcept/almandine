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
local printer = require("utils.printer")

local function get_help_string()
  local version = version_utils.get_version and version_utils.get_version() or "(unknown)"
  return (([[
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

local function run_cli(args)
  ---
  -- Executes the appropriate Almandine command based on arguments.
  -- @return boolean success True if command executed without fatal error.
  -- @return string|nil output_message Message for stdout (on success or non-fatal error).
  -- @return string|nil error_message Error message for stderr (on failure).
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
    return true, get_help_string() -- Return help string directly
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
      return true, get_help_string() -- Return help string
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
      -- Module help functions now RETURN the string
      local help_text = help_map[cmd]()
      return true, help_text
    else
      return false, nil, "Unknown command for help: " .. tostring(cmd)
    end
  end

  -- --- Command Execution ---
  local command = args[1]
  local printer_dep = { printer = printer } -- Create printer dependency table

  if command == "init" then
    -- Create dependencies table for init_project
    local init_deps = {
      prompt = function(prompt_text, default) -- Adjusted prompt wrapper
        io.write(prompt_text)
        local input = io.read()
        if input == "" or input == nil then
          return default
        else
          return input
        end
      end,
      printer = printer, -- Inject the printer
      save_manifest = manifest_utils.save_manifest, -- Use the required utility
    }
    -- Pass dependencies to init_project
    local ok, msg, err = init_module.init_project(init_deps)
    return ok, msg, err -- Directly return what init_project gives
  elseif command == "add" then
    local source = args[2]
    if not source then
      return false, nil, "Usage: almd add <source> [-d <dir>] [-n <dep_name>] [--verbose]"
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
        return false, nil, "Unknown or incomplete flag: " .. tostring(args[i])
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
      printer = printer, -- Inject printer
    })

    local final_message = ""

    if warning_occurred then
      -- Warnings go to stdout for now, could be stderr if preferred
      final_message = "Warning(s): " .. (warning_msg or "Unknown warning") .. "\n"
    end

    if not ok then
      local error_message = "Error: Add operation failed."
      if fatal_err then
        error_message = error_message .. "\n  Reason: " .. fatal_err
      end
      -- Return warning message on stdout even if error occurred
      return false, final_message:gsub("\n$", ""), error_message
    else
      -- Combine warnings and success message
      final_message = final_message .. "Dependency added successfully."
      return true, final_message
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
      printer = printer, -- Inject printer
    }
    local ok, msg = install_module.install_dependencies(dep_name, deps)
    if not ok then
      return false, nil, "Installation failed: " .. tostring(msg or "Unknown error")
    end
    return true, msg or "Installation complete."

  elseif command == "remove" or command == "rm" or command == "uninstall" or command == "un" then
    local dep_name = args[2]
    if not dep_name then
      return false, nil, "Usage: almd remove <dep_name>"
    end
    local ok, msg, err = remove_module.remove_dependency(
      dep_name,
      get_cached_manifest,
      manifest_utils.save_manifest,
      printer_dep -- Pass printer dependency
    )
    return ok, msg, err

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
      {
        downloader = downloader,
        printer = printer, -- Inject printer
      },
      add_module.resolve_latest_version,
      latest
    )
    -- Update likely prints its own progress, return a simple status
    return true, "Update process finished. Check output for details."

  elseif command == "run" then
    local script_name = args[2]
    if not script_name then
      return false, nil, "Usage: almd run <script_name>"
    end
    local deps = { manifest_loader = get_cached_manifest, printer = printer }
    local ok, msg, err = run_module.run_script(script_name, deps)
    return ok, msg, err -- run_script should return msg for stdout, err for stderr

  elseif command == "list" or command == "ls" then
    -- list_dependencies will now return the string
    local ok, list_str, err = list_module.list_dependencies(get_cached_manifest, printer_dep)
    return ok, list_str, err

  elseif command == "self" and args[2] == "uninstall" then
    local ok, err = self_module.uninstall_self(printer_dep)
    if ok then
      return true, "almd self uninstall: Success."
    else
      return false, nil, "almd self uninstall: Failed.\n" .. (err or "Unknown error.")
    end
  elseif command == "self" and args[2] == "update" then
    local ok, msg, err = self_module.self_update(printer_dep)
    if ok then
      return true, msg or "almd self update: Success."
    elseif msg == "Update staged for next run." then
      return true, msg -- Special case, considered success
    else
      return false, msg, "almd self update: Failed.\n" .. (err or "Unknown error.")
    end

  elseif not run_module.is_reserved_command(command) then
    -- Check for unambiguous script name if not a reserved command
    local deps = { manifest_loader = get_cached_manifest, printer = printer }
    local script_name = run_module.get_unambiguous_script(command, deps)
    if script_name then
      local ok, msg, err = run_module.run_script(script_name, deps)
      return ok, msg, err
    end
  end

  -- If command wasn't handled, return generic help/error on stderr
  return false, nil, "Unknown command or usage error: '" .. tostring(command) .. "'\n\n" .. get_help_string()
end

-- Wrapper for run_cli to handle exit code and printing
local function main(...)
  local ok, output_message, error_message = run_cli({ ... })

  if output_message then
    printer.stdout(output_message) -- Print regular output to stdout
  end

  if error_message then
    printer.stderr(error_message) -- Print errors to stderr
  end

  if not ok then
    os.exit(1)
  else
    os.exit(0) -- Ensure explicit exit 0 on success
  end
end

-- Get the script's own path using debug.getinfo
local script_path = debug.getinfo(1, "S").source:sub(2) -- Remove leading '@'
script_path = script_path:gsub("\\", "/") -- Normalize separators

-- Entry point check: Compare arg[0] with the script's path
if arg and arg[0] and script_path:match(arg[0] .. "$") then
  main(unpack(arg or {}, 1)) -- Use arg or empty table, unpack from index 1
end

-- Export the run_cli function for testing or programmatic use
return {
  run_cli = run_cli,
}
