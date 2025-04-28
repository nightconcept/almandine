--[[
  Add Command Module

  Provides functionality to add a dependency to the project manifest and download it to the lib directory.
]]--

--- Adds a dependency to the project manifest and downloads it.
-- @param dep_name string|nil Dependency name to add. If nil, inferred from source URL.
-- @param dep_source string Dependency source string (URL or table with url/path).
-- @param load_manifest function Function to load the manifest.
-- @param save_manifest function Function to save the manifest.
-- @param ensure_lib_dir function Function to ensure lib dir exists.
-- @param downloader table utils.downloader module.
local function add_dependency(dep_name, dep_source, load_manifest, save_manifest, ensure_lib_dir, downloader)
  ensure_lib_dir()
  local manifest, err = load_manifest()
  if not manifest then print(err) return end
  manifest.dependencies = manifest.dependencies or {}

  -- If dep_name is missing, infer from URL (filename minus .lua)
  if (not dep_name or dep_name == "") and type(dep_source) == "string" then
    local fname = dep_source:match("([^/]+)$")
    if fname then
      dep_name = fname:gsub("%.lua$", "")
    else
      print("Could not infer dependency name from source URL.")
      return
    end
  end
  if not dep_name or not dep_source then
    -- Nothing to add, exit early
    return
  end
  manifest.dependencies[dep_name] = dep_source
  local ok, err2 = save_manifest(manifest)
  if not ok then print(err2) return end
  print(string.format("Added dependency '%s' to project.lua.", dep_name))

  local name, source = dep_name, dep_source
  local out_path
  local url
  if type(source) == "table" and source.url and source.path then
    url = source.url
    out_path = source.path
  else
    url = source
    local filesystem_utils = require("utils.filesystem")
    out_path = filesystem_utils.join_path(
      "src",
      "lib",
      name .. ".lua"
    )
  end
  local ok3, err3 = downloader.download(url, out_path)
  if ok3 then
    print(string.format("Downloaded %s to %s",
      name, out_path))
  else
    print(string.format("Failed to download %s: %s", name, err3))
  end
end

---
-- Prints usage/help information for the `add` command.
-- Usage: almd add <dep_name> <source>
-- Adds a dependency to the project manifest and downloads it to the lib directory.
local function help_info()
  print([[
Usage: almd add <dep_name> <source>
       almd add <source>

Adds a dependency to your project. <dep_name> is the name (optional if source is a GitHub raw URL), <source> is a URL or
version specifier.
If <dep_name> is omitted, it will be inferred from the filename in the source URL.
Examples:
  almd add lunajson https://github.com/grafi-tt/lunajson/raw/master/lunajson.lua
  almd add https://github.com/grafi-tt/lunajson/raw/master/lunajson.lua
]])
end

return {
  add_dependency = add_dependency,
  help_info = help_info
}
