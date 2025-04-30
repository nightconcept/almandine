--[[
  Install Command Module

  Provides functionality to install all dependencies listed in project.lua or a specific dependency.
]]
--

local url_utils = require("utils.url") -- Require the url utility
local filesystem_utils = require("utils.filesystem") -- Moved require to top level

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

        if type(source) == "table" then
          if source.source then -- Standard lockfile entry with source/hash
            url = source.source
            out_path = filesystem_utils.join_path("src", "lib", name .. ".lua")
          elseif source.url then -- Handle manifest-style table entry {url=..., path=...}
            url = source.url
            out_path = source.path or filesystem_utils.join_path("src", "lib", name .. ".lua")
          else
            print(string.format("Skipping %s: Invalid table format in lockfile data", name))
            url = nil -- Ensure download is skipped
          end
        elseif type(source) == "string" then -- Handle URL string entry
          url = source
          out_path = filesystem_utils.join_path("src", "lib", name .. ".lua")
        else
          print(string.format("Skipping %s: Invalid source format in lockfile data", name))
          url = nil -- Ensure download is skipped
        end

        if url then -- Proceed only if a valid URL was extracted
          -- Normalize the URL
          local _, download_url, norm_err = url_utils.normalize_github_url(url)
          if norm_err then
            print(string.format("Skipping %s: Failed to normalize URL: %s", name, norm_err))
          else
            local ok3, err3 = (utils or { downloader = downloader }).downloader.download(download_url, out_path)
            if ok3 then
              print(string.format("Downloaded %s to %s", name, out_path))
            else
              print(string.format("Failed to download %s: %s", name, err3))
            end
          end
        end
      end
    end
  else
    -- Install from manifest
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
        local valid_source = true -- Flag to track if source is valid
        if type(source) == "table" and source.url and source.path then
          url = source.url
          out_path = source.path
        elseif type(source) == "string" then
          url = source
          out_path = filesystem_utils.join_path("src", "lib", name .. ".lua")
        else
          print(string.format("Skipping %s: Invalid source format in manifest", name))
          valid_source = false -- Mark source as invalid
        end

        -- Process only if the source format was valid
        if valid_source then
          -- Normalize the URL
          local _, download_url, norm_err = url_utils.normalize_github_url(url)
          if norm_err then
            print(string.format("Skipping %s: Failed to normalize URL: %s", name, norm_err))
          else
            local ok3, err3 = (utils or { downloader = downloader }).downloader.download(download_url, out_path)
            if ok3 then
              print(string.format("Downloaded %s to %s", name, out_path))
            else
              print(string.format("Failed to download %s: %s", name, err3))
            end
          end
        end
      end
    end
  end
end

-- Import the lockfile utility module
local lockfile = require("utils.lockfile")

local function help_info()
  print([[
Usage: almd install [<dep_name>]

Installs all dependencies listed in project.lua, or only <dep_name> if specified.
Example:
  almd install
  almd install lunajson
]])
end

return {
  install_dependencies = function(...)
    -- Call the internal install function. Lockfile update is no longer handled here.
    return install_dependencies(...)
  end,
  lockfile = lockfile,
  help_info = help_info,
}
