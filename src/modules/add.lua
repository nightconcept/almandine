--[[
  Add Module

  Provides functionality to add a dependency to the project manifest and download it to the lib directory.
  Extracted from main.lua as part of modularization.
]]--

--- Adds a dependency to the project manifest and downloads it.
-- @param dep_name string Dependency name to add.
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
  if not dep_name or not dep_source then
    -- Nothing to add, exit early
    return
  end
  if dep_name and dep_source then
    manifest.dependencies[dep_name] = dep_source
    local ok, err2 = save_manifest(manifest)
    if not ok then print(err2) return end
    print(string.format("Added dependency '%s' to project.lua.", dep_name))
  end
  local name, source = dep_name, dep_source
  local out_path
  local url
  if type(source) == "table" and source.url and source.path then
    url = source.url
    out_path = source.path
  else
    url = source
    out_path = "src/lib/" .. name .. ".lua"
  end
  local ok3, err3 = downloader.download(url, out_path)
  if ok3 then
    print(string.format("Downloaded %s to %s", name, out_path))
  else
    print(string.format("Failed to download %s: %s", name, err3))
  end
end

return {
  add_dependency = add_dependency
}
