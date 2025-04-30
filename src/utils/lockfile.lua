--[[
  Lockfile Utility Module

  Centralizes all lockfile operations for Almandine. Provides functions to generate, serialize, write,
  and modify the lockfile (almd-lock.lua) in a consistent, reusable way.
]]
--

--- Lockfile schema version (increment if schema changes)
local API_VERSION = "1"

local lockfile = {}
local io = io
local tostring = tostring

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
    if dep.version then
      entry.version = dep.version
    end
    if dep.source then
      entry.source = dep.source
    end
    pkgs[name] = entry
  end
  return {
    api_version = API_VERSION,
    package = pkgs,
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
    local lines = { "{" }
    for k, v in pairs(tbl) do
      local key
      -- Always format string keys as ["key"] = for consistency in lockfile
      if type(k) == "string" then
        key = string.format('["%s"] = ', k)
      else
        key = ("[" .. tostring(k) .. "] = ")
      end
      if type(v) == "table" then
        local serialized = serialize(v, indent + 1)
        table.insert(lines, pad .. "  " .. key .. serialized .. ",")
      elseif type(v) == "string" then
        table.insert(lines, pad .. "  " .. key .. string.format('"%s"', v) .. ",")
      else
        table.insert(lines, pad .. "  " .. key .. tostring(v) .. ",")
      end
    end
    table.insert(lines, pad .. "}")
    return table.concat(lines, "\n")
  end
  local result = "return " .. serialize(lockfile_table, 0) .. "\n"
  return result
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
  if not file then
    return false, err
  end
  file:write(content)
  file:close()
  return true, path
end

---
-- Loads and parses the lockfile from disk.
-- @param path string (optional) Path to lockfile (default: "almd-lock.lua")
-- @return table|nil, string|nil Lockfile table if successful, nil and error message otherwise
function lockfile.load_lockfile(path)
  path = path or "almd-lock.lua"
  -- Check existence first to give a clearer error
  local file_check = io.open(path, "r")
  if not file_check then
    return nil, "Could not read lockfile: " .. path .. " (does not exist or permissions error)"
  end
  file_check:close()

  -- Now attempt to load it as a Lua chunk
  local chunk, load_err = loadfile(path)
  if not chunk then
    return nil, "Could not load lockfile chunk: " .. path .. " (" .. (load_err or "syntax error?") .. ")"
  end

  -- Execute the chunk in a protected call
  local ok, lock_data = pcall(chunk)
  if not ok then
    return nil, "Error executing lockfile chunk: " .. path .. " (" .. tostring(lock_data) .. ")"
  end

  -- Validate basic structure
  if type(lock_data) ~= "table" or type(lock_data.package) ~= "table" then
    return nil, "Malformed lockfile: Invalid structure in " .. path
  end

  -- Return only the dependency package data for consistency with how it was used before
  -- Or maybe return the full table? Let's return the full table for now.
  -- return lock_data.package, nil
  return lock_data, nil
end

---
-- Removes a dependency from the lockfile on disk.
-- @param dep_name string Name of dependency to remove
-- @param path string (optional) Path to lockfile (default: "almd-lock.lua")
-- @return boolean, string True if successful, false and error message otherwise
function lockfile.remove_dep_from_lockfile(dep_name, path)
  path = path or "almd-lock.lua"
  local chunk = loadfile(path)
  if not chunk then
    return false, "Lockfile not found"
  end
  local ok, lock = pcall(chunk)
  if not ok or type(lock) ~= "table" or type(lock.package) ~= "table" then
    return false, "Malformed lockfile"
  end
  if lock.package[dep_name] then
    lock.package[dep_name] = nil
    return lockfile.write_lockfile(lock, path)
  end
  return true, path -- No-op if dep not present
end

---
-- Updates the lockfile from a manifest loader function.
-- @param load_manifest function Function to load the manifest
-- @return boolean, string True if successful, false and error message otherwise
function lockfile.update_lockfile_from_manifest(load_manifest)
  local manifest, err = load_manifest()
  if not manifest then
    return false, err or "Could not load manifest"
  end
  local resolved_deps = {}
  for name, dep in pairs(manifest.dependencies or {}) do
    local dep_entry = type(dep) == "table" and dep or { url = dep }
    -- Compute hash (placeholder: use URL as hash; replace with real hash logic if available)
    local hash = dep_entry.url or tostring(dep)
    resolved_deps[name] = { hash = hash, source = dep_entry.url or tostring(dep) }
  end
  local lockfile_table = lockfile.generate_lockfile_table(resolved_deps)
  return lockfile.write_lockfile(lockfile_table)
end

return lockfile
