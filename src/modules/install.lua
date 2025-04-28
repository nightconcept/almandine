--[[
  Install Module

  Provides functionality to install all dependencies listed in project.lua or a specific dependency. Extracted from main.lua as part of modularization.
]]--

---
-- Installs dependencies from the manifest or lockfile.
-- If dep_name is provided, only installs that dependency.
-- @param dep_name string|nil Dependency name to install (or all if nil).
-- @param load_manifest function Function to load the manifest.
-- @param ensure_lib_dir function Function to ensure lib dir exists.
-- @param downloader table utils.downloader module.
-- @param lockfile_deps table|nil Lockfile dependency table (optional)
local function install_dependencies(dep_name, load_manifest, ensure_lib_dir, downloader, lockfile_deps)
  ensure_lib_dir()
  local deps = {}
  if lockfile_deps then
    deps = lockfile_deps
  else
    local manifest, err = load_manifest()
    if not manifest then print(err) return end
    deps = manifest.dependencies or {}
  end
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
      local ok3, err3 = utils.downloader.download(url, out_path)
      if ok3 then
        print(string.format("Downloaded %s to %s", name, out_path))
      else
        print(string.format("Failed to download %s: %s", name, err3))
      end
    end
  end
end

--[[
  Lockfile Management Module (migrated from src/lib/lockfile.lua)
  Provides functions to generate, serialize, and write the Almandine lockfile (`almd-lock.lua`).
  The lockfile captures exact dependency versions and hashes for reproducible builds.
]]--

local lockfile = {}

local io = io
local table = table
local tostring = tostring

--- Lockfile schema version (increment if schema changes)
local API_VERSION = "1"

---
-- Generates a lockfile table from resolved dependencies.
-- @param resolved_deps table Table of resolved dependencies. Each key is a package name, value is a table with fields:
--                          - version (string, optional)
--                          - hash (string, required)
--                          - source (string, optional)
-- @return table Lockfile table matching the schema
function lockfile.generate_lockfile_table(resolved_deps)
  assert(type(resolved_deps) == "table", "resolved_deps must be a table")
  local pkgs = {}
  for name, dep in pairs(resolved_deps) do
    assert(type(dep) == "table", "Dependency entry must be a table")
    assert(dep.hash, "Dependency '" .. name .. "' must have a hash")
    local entry = { hash = dep.hash }
    if dep.version then entry.version = dep.version end
    if dep.source then entry.source = dep.source end
    pkgs[name] = entry
  end
  return {
    api_version = API_VERSION,
    package = pkgs
  }
end

---
-- Serializes a lockfile table to a string (Lua syntax).
-- @param lockfile_table table Lockfile table
-- @return string Lua code as string
function lockfile.serialize_lockfile(lockfile_table)
  assert(type(lockfile_table) == "table", "lockfile_table must be a table")
  local function serialize(tbl, indent)
    indent = indent or 0
    local pad = string.rep("  ", indent)
    local lines = {"{"}
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
  return "return " .. serialize(lockfile_table, 0) .. "\n"
end

---
-- Writes the lockfile to disk as `almd-lock.lua`.
-- @param lockfile_table table Lockfile table
-- @param path string (optional) Path to write to (default: "almd-lock.lua" in project root)
-- @return boolean, string True and path if successful, false and error message otherwise
function lockfile.write_lockfile(lockfile_table, path)
  path = path or "almd-lock.lua"
  local content = lockfile.serialize_lockfile(lockfile_table)
  local file, err = io.open(path, "w")
  if not file then return false, err end
  file:write(content)
  file:close()
  return true, path
end

return {
  install_dependencies = install_dependencies,
  lockfile = lockfile
}
