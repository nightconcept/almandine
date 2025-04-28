--[[
  Run Command Module

  Provides logic for executing scripts defined in the `scripts` table of project.lua. Used by the main CLI entrypoint for the `run` command and for direct script invocation if unambiguous.
]]--

---
-- Executes a script by name from the project manifest.
-- @param script_name [string] The key of the script in the scripts table.
-- @param manifest_loader [table] The manifest loader module.
-- @return [boolean, string] True and output if successful, false and error message otherwise.
local function run_script(script_name, manifest_loader)
  local manifest, err = manifest_loader.safe_load_project_manifest("project.lua")
  if not manifest then
    return false, err
  end
  local scripts = manifest.scripts or {}
  local command = scripts[script_name]
  if not command then
    return false, string.format("Script '%s' not found in project.lua.", script_name)
  end
  print(string.format("Running script '%s': %s", script_name, command))
  local ok, exit_reason, code = os.execute(command)
  if ok then
    print(string.format("Script '%s' completed successfully.", script_name))
    return true, nil
  else
    print(string.format("Script '%s' failed (reason: %s, code: %s)", script_name, tostring(exit_reason), tostring(code)))
    return false, string.format("Script '%s' failed (reason: %s, code: %s)", script_name, tostring(exit_reason), tostring(code))
  end
end

---
-- Determines if a string is a reserved command name.
-- @param name [string]
-- @return [boolean]
local function is_reserved_command(name)
  local reserved = {
    ["init"] = true, ["add"] = true, ["i"] = true, ["install"] = true, ["in"] = true, ["ins"] = true,
    ["remove"] = true, ["rm"] = true, ["uninstall"] = true, ["un"] = true,
    ["update"] = true, ["up"] = true, ["upgrade"] = true, ["run"] = true, ["list"] = true,
  }
  return reserved[name] == true
end

---
-- Finds a matching script if the name is unambiguous.
-- @param name [string] The candidate script name.
-- @param manifest_loader [table]
-- @return [string|nil] The script name if unambiguous, or nil.
local function get_unambiguous_script(name, manifest_loader)
  local manifest, err = manifest_loader.safe_load_project_manifest("project.lua")
  if not manifest or not manifest.scripts then return nil end
  if manifest.scripts[name] then return name end
  return nil
end

return {
  run_script = run_script,
  is_reserved_command = is_reserved_command,
  get_unambiguous_script = get_unambiguous_script,
}
