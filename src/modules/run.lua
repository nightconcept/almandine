--[[
  Run Command Module

  Provides logic for executing scripts defined in the `scripts` table of project.lua.
  Used by the main CLI entrypoint for the `run` command and for direct script invocation if unambiguous.
]]
--

---
-- Executes a script by name from the project manifest using provided dependencies.
-- @param script_name string The key of the script in the scripts table.
-- @param deps table Dependencies: { manifest_loader, executor? }.
--               `manifest_loader` is a function or module with safe_load_project_manifest.
--               `executor` is an optional function for command execution (defaults to os.execute).
-- @return boolean, string True and output if successful, false and error message otherwise.
local function run_script(script_name, deps)
  local manifest_loader = deps.manifest_loader
  local executor = deps.executor or os.execute

  -- Handle manifest_loader being either a function or a module
  local load_manifest = type(manifest_loader) == "function" and manifest_loader
    or manifest_loader.safe_load_project_manifest

  local manifest = load_manifest("project.lua")
  if not manifest then
    return false, "Failed to load project manifest."
  end
  local scripts = manifest.scripts or {}
  if not scripts or not scripts[script_name] then
    print(string.format("Script '%s' not found in project.lua.", script_name))
    return false, string.format("Script '%s' not found in project.lua.", script_name)
  end
  local script = scripts[script_name]
  local cmd = script.cmd or script
  local args = script.args or {}
  local command = cmd
  if #args > 0 then
    command = cmd .. " " .. table.concat(args, " ")
  end
  print(string.format("Running script '%s': %s", script_name, command))
  local ok, exit_reason, code = executor(command)
  if ok then
    print(string.format("Script '%s' completed successfully.", script_name))
    return true, nil
  else
    print(
      string.format("Script '%s' failed (reason: %s, code: %s)", script_name, tostring(exit_reason), tostring(code))
    )
    return false,
      string.format("Script '%s' failed (reason: %s, code: %s)", script_name, tostring(exit_reason), tostring(code))
  end
end

---
-- Determines if a string is a reserved command name.
-- @param name string
-- @return boolean
local function is_reserved_command(name)
  local reserved = {
    ["init"] = true,
    ["add"] = true,
    ["i"] = true,
    ["install"] = true,
    ["in"] = true,
    ["ins"] = true,
    ["remove"] = true,
    ["rm"] = true,
    ["uninstall"] = true,
    ["un"] = true,
    ["update"] = true,
    ["up"] = true,
    ["upgrade"] = true,
    ["run"] = true,
    ["list"] = true,
  }
  return reserved[name] == true
end

---
-- Finds a matching script if the name is unambiguous using provided dependencies.
-- @param name string The candidate script name.
-- @param deps table Dependencies: { manifest_loader }.
--               `manifest_loader` is a function or module with safe_load_project_manifest.
-- @return string|nil The script name if unambiguous, or nil.
local function get_unambiguous_script(name, deps)
  local manifest_loader = deps.manifest_loader
  -- Handle manifest_loader being either a function or a module
  local load_manifest = type(manifest_loader) == "function" and manifest_loader
    or manifest_loader.safe_load_project_manifest

  local manifest = load_manifest("project.lua")
  if not manifest or not manifest.scripts then
    return nil
  end
  if manifest.scripts[name] then
    return name
  end
  return nil
end

---
-- Prints usage/help information for the `run` command.
-- Usage: almd run <script_name>
-- Executes a script defined in project.lua.
local function help_info()
  print([[
Usage: almd run <script_name>

Executes a script defined in the `scripts` table of project.lua.
Example:
  almd run test
]])
end

return {
  run_script = run_script,
  is_reserved_command = is_reserved_command,
  get_unambiguous_script = get_unambiguous_script,
  help_info = help_info,
}
