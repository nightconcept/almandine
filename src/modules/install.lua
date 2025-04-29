--[[
  Install Command Module

  Provides functionality to install all dependencies listed in project.lua or a specific dependency.
]]
--

---
-- Installs dependencies from the manifest or lockfile.
-- If dep_name is provided, only installs that dependency.
-- @param dep_name string|nil Dependency name to install (or all if nil).
-- @param load_manifest function Function to load the manifest.
-- @param ensure_lib_dir function Function to ensure lib dir exists.
-- @param downloader table utils.downloader module.
-- @param utils table Utils module (must provide .downloader).
-- @param lockfile_deps table|nil Lockfile dependency table (optional)
local function install_dependencies(dep_name, load_manifest, ensure_lib_dir, downloader, utils, lockfile_deps)
  ensure_lib_dir()
  if lockfile_deps then
    local deps = lockfile_deps
    for name, source in pairs(deps) do
      if (not dep_name) or (dep_name == name) then
        local out_path
        local url
        if type(source) == "table" and source.url and source.path then
          url = source.url
          out_path = source.path
        else
          url = source
          local filesystem_utils = require("utils.filesystem")
          out_path = filesystem_utils.join_path("src", "lib", name .. ".lua")
        end
        local ok3, err3 = (utils or { downloader = downloader }).downloader.download(url, out_path)
        if ok3 then
          print(string.format("Downloaded %s to %s", name, out_path))
        else
          print(string.format("Failed to download %s: %s", name, err3))
        end
      end
    end
  else
    local manifest, err = load_manifest()
    if not manifest then
      print(err)
      return
    end
    local deps = manifest.dependencies or {}
    for name, source in pairs(deps) do
      if (not dep_name) or (dep_name == name) then
        local out_path
        local url
        if type(source) == "table" and source.url and source.path then
          url = source.url
          out_path = source.path
        else
          url = source
          local filesystem_utils = require("utils.filesystem")
          out_path = filesystem_utils.join_path("src", "lib", name .. ".lua")
        end
        local ok3, err3 = (utils or { downloader = downloader }).downloader.download(url, out_path)
        if ok3 then
          print(string.format("Downloaded %s to %s", name, out_path))
        else
          print(string.format("Failed to download %s: %s", name, err3))
        end
      end
    end
  end
end

-- Import the lockfile utility module
local lockfile = require("utils.lockfile")

local function help_info()
  print([[\nUsage: almd install [<dep_name>]

Installs all dependencies listed in project.lua, or only <dep_name> if specified.
Example:
  almd install
  almd install lunajson
]])
end

return {
  install_dependencies = function(...)
    local _, load_manifest, _, _, _, lockfile_deps = ...
    local res = install_dependencies(...)
    -- Only update lockfile if installing from manifest (not lockfile_deps)
    if not lockfile_deps and type(load_manifest) == "function" then
      local ok_lock, err_lock = lockfile.update_lockfile_from_manifest(load_manifest)
      if ok_lock then
        print("Updated lockfile: almd-lock.lua")
      else
        print("Failed to update lockfile: " .. tostring(err_lock))
      end
    end
    return res
  end,
  lockfile = lockfile,
  help_info = help_info,
}
