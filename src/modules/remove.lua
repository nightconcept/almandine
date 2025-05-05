--[[
  Remove Command Module

  Provides functionality to remove a dependency from the project manifest and delete the corresponding
  file from the lib directory.
]]
--

---TODO: remove this once we have a pass over this file
-- luacheck: ignore
---@class RemoveDeps
---@field load_manifest fun(): table, string?
---@field save_manifest fun(manifest: table): boolean, string?
---@field printer table Printer utility with stdout/stderr methods.

--- Removes a dependency from project.lua and deletes its file.
-- @param dep_name string Dependency name to remove.
-- @param load_manifest function Function to load the manifest.
-- @param save_manifest function Function to save the manifest.
-- @param deps RemoveDeps Table containing dependencies.
-- @return boolean success True if successful, false otherwise.
-- @return string|nil output_message Message for stdout.
-- @return string|nil error_message Message for stderr.
local function remove_dependency(dep_name, load_manifest, save_manifest, deps)
  local output_messages = {}
  local error_messages = {}

  local manifest, manifest_err = load_manifest()
  if not manifest then
    table.insert(error_messages, "Failed to load manifest: " .. (manifest_err or "Unknown error"))
    return false, nil, table.concat(error_messages, "\n")
  end
  manifest.dependencies = manifest.dependencies or {}
  if not manifest.dependencies[dep_name] then
    table.insert(error_messages, string.format("Error: Dependency '%s' not found in project.lua.", dep_name))
    return false, nil, table.concat(error_messages, "\n")
  end
  local dep = manifest.dependencies[dep_name]
  local dep_path
  if type(dep) == "table" and dep.path then
    dep_path = dep.path
  elseif _G.dependency_add_test_paths and _G.dependency_add_test_paths[dep_name] then
    dep_path = _G.dependency_add_test_paths[dep_name]
  else
    local filesystem_utils = require("utils.filesystem")
    dep_path = filesystem_utils.join_path("src", "lib", dep_name .. ".lua")
  end
  manifest.dependencies[dep_name] = nil
  local ok, err2 = save_manifest(manifest)
  if not ok then
    table.insert(error_messages, "Error saving manifest: " .. (err2 or "Unknown error"))
    return false, nil, table.concat(error_messages, "\n") -- Fail early if manifest save fails
  end
  table.insert(output_messages, string.format("Removed dependency '%s' from project.lua.", dep_name))

  local removed = os.remove(dep_path)
  if removed then
    table.insert(output_messages, string.format("Deleted file %s", dep_path))
  else
    table.insert(error_messages, string.format("Warning: Could not delete file %s (may not exist or permissions error)", dep_path))
  end

  -- Remove entry from lockfile (almd-lock.lua)
  local lockfile_mod = require("utils.lockfile")
  local ok_lock, err_lock = lockfile_mod.remove_dep_from_lockfile(dep_name)
  if ok_lock then
    table.insert(output_messages, string.format("Updated lockfile: almd-lock.lua (removed entry for '%s')", dep_name))
  else
    table.insert(error_messages, "Warning: Failed to update lockfile: " .. tostring(err_lock))
  end

  -- Combine messages for return
  local final_output = table.concat(output_messages, "\n")
  local final_error = nil
  if #error_messages > 0 then
    final_error = table.concat(error_messages, "\n")
  end

  return true, final_output, final_error
end

---
-- Prints usage/help information for the `remove` command.
-- Usage: almd remove <dep_name>
-- Removes a dependency from the project and deletes its file from the lib directory.
local function help_info()
  print([[\nUsage: almd remove <dep_name>

Removes a dependency from your project and deletes the corresponding file.
Example:
  almd remove lunajson
]])
end

return {
  remove_dependency = remove_dependency,
  help_info = help_info,
}
