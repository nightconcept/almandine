--[[
  Remove Command Module

  Provides functionality to remove a dependency from the project manifest and delete the corresponding
  file from the lib directory.
]]
--

--- Removes a dependency from project.lua and deletes its file.
-- @param dep_name string Dependency name to remove.
-- @param load_manifest function Function to load the manifest.
-- @param save_manifest function Function to save the manifest.
local function remove_dependency(dep_name, load_manifest, save_manifest)
  local manifest, err = load_manifest()
  if not manifest then
    print(err)
    return
  end
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
    local filesystem_utils = require("utils.filesystem")
    dep_path = filesystem_utils.join_path("src", "lib", dep_name .. ".lua")
  end
  manifest.dependencies[dep_name] = nil
  local ok, err2 = save_manifest(manifest)
  if not ok then
    print(err2)
    return
  end
  print(string.format("Removed dependency '%s' from project.lua.", dep_name))
  local removed = os.remove(dep_path)
  if removed then
    print(string.format("Deleted file %s", dep_path))
  else
    print(string.format("Warning: Could not delete file %s (may not exist)", dep_path))
  end

  -- Remove entry from lockfile (almd-lock.lua)
  local lockfile_path = "almd-lock.lua"
  local lockfile_chunk = loadfile(lockfile_path)
  if lockfile_chunk then
    local ok_lock, lockfile = pcall(lockfile_chunk)
    if ok_lock and type(lockfile) == "table" and type(lockfile.package) == "table" then
      if lockfile.package[dep_name] then
        lockfile.package[dep_name] = nil
        -- Write updated lockfile
        local file, err = io.open(lockfile_path, "w")
        if file then
          file:write("return ")
          local function serialize(tbl, indent)
            indent = indent or 0
            local pad = string.rep("  ", indent)
            local lines = { "{" }
            for k, v in pairs(tbl) do
              local key = (type(k) == "string" and string.format("%s = ", k)) or ("[" .. tostring(k) .. "] = ")
              if type(v) == "table" then
                table.insert(lines, pad .. "  " .. key .. serialize(v, indent + 1) .. ",")
              elseif type(v) == "string" then
                table.insert(lines, pad .. "  " .. key .. string.format('"%s"', v) .. ",")
              else
                table.insert(lines, pad .. "  " .. key .. tostring(v) .. ",")
              end
            end
            table.insert(lines, pad .. "}")
            return table.concat(lines, "\n")
          end
          file:write(serialize(lockfile, 0) .. "\n")
          file:close()
          print("Updated lockfile: almd-lock.lua (removed entry for '" .. dep_name .. "')")
        else
          print("Failed to update lockfile: " .. tostring(err))
        end
      end
    end
  end
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
