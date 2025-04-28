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

local downloader = require("downloader")
local manifest_loader = require("manifest_loader")
local init_module = require("modules.init")
local add_module = require("modules.add")

local function load_manifest()
  local manifest, err = manifest_loader.safe_load_project_manifest("project.lua")
  if not manifest then return nil, err end
  return manifest, nil
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
    if type(v) == "table" and v.url and v.path then
      file:write(string.format("    [%q] = { url = %q, path = %q },\n", k, v.url, v.path))
    else
      file:write(string.format("    [%q] = \"%s\",\n", k, v))
    end
  end
  file:write("  }\n}\n")
  file:close()
  return true, nil
end

--- Ensures the lib directory exists.
local function ensure_lib_dir()
  -- Cross-platform directory creation
  local sep = package.config:sub(1,1)
  local path = "src" .. sep .. "lib"
  local ok
  if sep == "\\" then
    -- Windows: mkdir returns 0 if directory created or already exists
    ok = os.execute("mkdir " .. path .. " >nul 2>&1")
  else
    -- Unix: use -p for parent dirs
    ok = os.execute("mkdir -p " .. path .. " >/dev/null 2>&1")
  end
  -- Remove noisy warning, only print if directory is truly missing (optional: check existence)
end

--- Installs all dependencies listed in project.lua or a specific dependency.
-- @param dep_name string|nil Dependency name to install (or all if nil).
-- @param dep_source string|nil Dependency source string (if installing a new dep).
local function install_dependency(dep_name, dep_source)
  ensure_lib_dir()
  local manifest, err = load_manifest()
  if not manifest then print(err) return end
  manifest.dependencies = manifest.dependencies or {}
  if dep_name and dep_source then
    manifest.dependencies[dep_name] = dep_source
    local ok, err2 = save_manifest(manifest)
    if not ok then print(err2) return end
    print(string.format("Added dependency '%s' to project.lua.", dep_name))
  end
  for name, source in pairs(manifest.dependencies) do
    if (not dep_name) or (dep_name == name) then
      local out_path
      local url
      if type(source) == "table" and source.url and source.path then
        url = source.url
        out_path = source.path
      else
        url = source
        if _G.dependency_add_test_paths and _G.dependency_add_test_paths[name] then
          out_path = _G.dependency_add_test_paths[name]
        else
          out_path = string.format("src/lib/%s.lua", name)
        end
      end
      print(string.format("Installing %s from %s ...", name, url))
      local ok, err3 = downloader.download_file(url, out_path)
      if ok then
        print(string.format("Downloaded %s to %s", name, out_path))
      else
        print(string.format("Failed to download %s: %s", name, err3))
      end
    end
  end
end

--- Removes a dependency from project.lua and deletes its file.
-- @param dep_name string Dependency name to remove.
local function remove_dependency(dep_name)
  local manifest, err = load_manifest()
  if not manifest then print(err) return end
  manifest.dependencies = manifest.dependencies or {}
  if not manifest.dependencies[dep_name] then
    print(string.format("Dependency '%s' not found in project.lua.", dep_name))
    return
  end
  local dep = manifest.dependencies[dep_name]
  local dep_path
  if type(dep) == "table" and dep.path then
    dep_path = dep.path
  elseif _G.dependency_add_test_paths and _G.dependency_add_test_paths[dep_name] then
    dep_path = _G.dependency_add_test_paths[dep_name]
  else
    dep_path = string.format("src/lib/%s.lua", dep_name)
  end
  manifest.dependencies[dep_name] = nil
  local ok, err2 = save_manifest(manifest)
  if not ok then print(err2) return end
  print(string.format("Removed dependency '%s' from project.lua.", dep_name))
  os.remove(dep_path)
  print(string.format("Deleted file %s", dep_path))
end

-- Helper: Parse Lua version string to numeric table
local function parse_lua_version(ver_str)
  local major, minor, patch = ver_str:match("^(%d+)%.(%d+)%.?(%d*)")
  return tonumber(major), tonumber(minor), tonumber(patch) or 0
end

-- Helper: Compare two Lua versions (major, minor, patch)
local function compare_lua_versions(a, b)
  if a[1] ~= b[1] then return a[1] - b[1] end
  if a[2] ~= b[2] then return a[2] - b[2] end
  return (a[3] or 0) - (b[3] or 0)
end

-- Helper: Check if current Lua version matches constraint string
local function lua_version_satisfies(constraint)
  if not constraint or constraint == "" then return true end
  local op, ver = constraint:match("^([<>]=?|=)%s*(%d+%.%d+)")
  if not op or not ver then return true end
  local req_major, req_minor = ver:match("(%d+)%.(%d+)")
  req_major, req_minor = tonumber(req_major), tonumber(req_minor)
  local cur_major, cur_minor = _VERSION:match("Lua (%d+)%.(%d+)")
  cur_major, cur_minor = tonumber(cur_major), tonumber(cur_minor)
  if not (cur_major and cur_minor and req_major and req_minor) then return true end
  if op == ">=" then
    return cur_major > req_major or (cur_major == req_major and cur_minor >= req_minor)
  elseif op == ">" then
    return cur_major > req_major or (cur_major == req_major and cur_minor > req_minor)
  elseif op == "<=" then
    return cur_major < req_major or (cur_major == req_major and cur_minor <= req_minor)
  elseif op == "<" then
    return cur_major < req_major or (cur_major == req_major and cur_minor < req_minor)
  elseif op == "=" then
    return cur_major == req_major and cur_minor == req_minor
  end
  return true
end

-- Check Lua version constraint from project.lua manifest
local function check_lua_version()
  local manifest, err = load_manifest()
  if not manifest then return true end
  if manifest.lua then
    if not lua_version_satisfies(manifest.lua) then
      io.stderr:write(string.format(
        "Error: Project requires Lua version %s, but running %s\n",
        manifest.lua, _VERSION
      ))
      os.exit(1)
    end
  end
end

local function main(...)
  --- The main entry point for the Almandine CLI application.
  --
  -- @param ... string CLI arguments.
  check_lua_version()
  local args = {...}
  if args[1] == "init" then
    init_module.init_project()
    return
  elseif args[1] == "add" or args[1] == "i" then
    -- Usage: almandine add <dep_name> <source>
    if args[2] and args[3] then
      add_module.add_dependency(args[2], args[3], load_manifest, save_manifest, ensure_lib_dir, downloader)
    else
      print("Usage: almandine add <dep_name> <source>")
    end
    return
  elseif args[1] == "remove" then
    if args[2] then
      remove_dependency(args[2])
    else
      print("Usage: almandine remove <dep_name>")
    end
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

-- Expose install_dependency and remove_dependency for testing
return {
  install_dependency = install_dependency,
  remove_dependency = remove_dependency,
  main = main
}
