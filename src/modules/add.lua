--[[
  Add Command Module

  Provides functionality to add a dependency to the project manifest and download it to the lib directory.
]]
--

--- Adds a dependency to the project manifest and downloads it.
-- @param dep_name string|nil Dependency name to add. If nil, inferred from source URL.
-- @param dep_source string Dependency source string (URL or table with url/path).
-- @param load_manifest function Function to load the manifest.
-- @param save_manifest function Function to save the manifest.
-- @param ensure_lib_dir function Function to ensure lib dir exists.
-- @param downloader table utils.downloader module.
-- @param dest_dir string|nil Optional destination directory for the installed file.
local function add_dependency(dep_name, dep_source, load_manifest, save_manifest, ensure_lib_dir, downloader, dest_dir)
  ensure_lib_dir()
  local manifest, err = load_manifest()
  if not manifest then
    print(err)
    return
  end
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

  local dep_entry
  local out_path
  if dest_dir then
    -- Store as table with url and path
    dep_entry = { url = dep_source, path = dest_dir }
    out_path = dest_dir
  elseif type(dep_source) == "table" and dep_source.path then
    dep_entry = dep_source
    out_path = dep_source.path
  else
    dep_entry = dep_source
    local filesystem_utils = require("utils.filesystem")
    out_path = filesystem_utils.join_path("src", "lib", dep_name .. ".lua")
  end
  manifest.dependencies[dep_name] = dep_entry
  local ok, err2 = save_manifest(manifest)
  if not ok then
    print(err2)
    return
  end
  print(string.format("Added dependency '%s' to project.lua.", dep_name))

  local url = (type(dep_entry) == "table" and dep_entry.url) or dep_entry
  local ok3, err3 = downloader.download(url, out_path)
  if ok3 then
    print(string.format("Downloaded %s to %s", dep_name, out_path))
  else
    print(string.format("Failed to download %s: %s", dep_name, err3))
    return
  end

  -- Generate and write lockfile after successful add
  local lockfile_mod = require("utils.lockfile")
  -- Build resolved_deps table for lockfile (minimal: name and hash)
  local resolved_deps = {}
  for name, dep in pairs(manifest.dependencies or {}) do
    local lock_dep_entry = type(dep) == "table" and dep or { url = dep }
    -- Compute hash (placeholder: use URL as hash; replace with real hash logic if available)
    local hash = lock_dep_entry.url or tostring(dep)
    resolved_deps[name] = { hash = hash, source = lock_dep_entry.url or tostring(dep) }
  end
  local lockfile_table = lockfile_mod.generate_lockfile_table(resolved_deps)
  local ok_lock, err_lock = lockfile_mod.write_lockfile(lockfile_table)
  if ok_lock then
    print("Updated lockfile: almd-lock.lua")
  else
    print("Failed to update lockfile: " .. tostring(err_lock))
  end
end

---
-- Prints usage/help information for the `add` command.
-- Usage: almd add <source> [-d <dir>] [-n <dep_name>]
-- Adds a dependency to the project manifest and downloads it to the lib directory or specified path.
local function help_info()
  print([[\nUsage: almd add <source> [-d <dir>] [-n <dep_name>]

Adds a dependency to your project. <source> is a URL or version specifier.
-d <dir> sets the install path (file, not just directory). If omitted, installs to src/lib/<dep_name>.lua.
-n <dep_name> sets the dependency name. If omitted, it is inferred from the source filename.

Examples:
  almd add https://github.com/grafi-tt/lunajson/raw/master/lunajson.lua
  almd add https://github.com/grafi-tt/lunajson/raw/master/lunajson.lua -n lunajson
  almd add https://example.com/foo.lua -n foo -d src/lib/custom/foo.lua
]])
end

return {
  add_dependency = add_dependency,
  help_info = help_info,
}
