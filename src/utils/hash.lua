--[[
  Hash Utility Module

  Provides functionality to extract Git commit hashes from repository URLs.
  Used primarily for lockfile generation to track dependency versions.
]]

--- Extracts the commit hash from a GitHub URL
-- @param url string The GitHub URL to parse
-- @return string|nil The commit hash if found, or nil if not a GitHub URL or no hash found
-- @return string|nil Error message if there was an error
local function extract_github_hash(url)
  if type(url) ~= "string" then
    return nil, "URL must be a string"
  end

  -- Match GitHub blob URLs with commit hashes
  -- Example: https://github.com/owner/repo/blob/abc123.../file.lua
  local hash = url:match("/blob/([0-9a-f]+)/")
  if hash and #hash >= 7 then -- GitHub hashes are at least 7 chars
    return hash
  end

  -- Match GitHub raw URLs with commit hashes
  -- Example: https://raw.githubusercontent.com/owner/repo/abc123.../file.lua
  hash = url:match("githubusercontent%.com/[^/]+/[^/]+/([0-9a-f]+)/")
  if hash and #hash >= 7 then
    return hash
  end

  return nil, "No commit hash found in GitHub URL"
end

--- Generates a hash for a dependency entry
-- @param dep_entry string|table The dependency entry (URL string or table with url/path)
-- @return string|nil The hash of the dependency, or nil if there was an error
-- @return string|nil Error message if there was an error
local function hash_dependency(dep_entry)
  local url
  if type(dep_entry) == "string" then
    url = dep_entry
  elseif type(dep_entry) == "table" and dep_entry.url then
    url = dep_entry.url
  else
    return nil, "Invalid dependency entry format"
  end

  -- Try to extract GitHub commit hash
  local hash, err = extract_github_hash(url)
  if hash then
    return hash
  end

  -- If no hash found in URL, return the error from extract_github_hash
  return nil, err or "URL does not contain a commit hash. Please use a URL with an explicit commit hash."
end

--- Calculates the SHA512 hash of a file using external command.
-- NOTE: Requires 'sha512sum' (Linux/macOS) or 'CertUtil' (Windows) to be in the PATH.
-- @param file_path string Path to the file.
-- @return string|nil The hex-encoded SHA512 hash, or nil on error.
-- @return string|nil Error message if calculation failed.
local function calculate_sha512(file_path)
  local command
  local os_type = package.config:sub(1, 1) == "\\" and "windows" or "unix"

  if os_type == "unix" then
    -- Assumes sha512sum is available
    command = string.format("sha512sum '%s'", file_path)
  else -- windows
    -- Assumes CertUtil is available
    command = string.format('CertUtil -hashfile "%s" SHA512', file_path)
  end

  local handle = io.popen(command)
  if not handle then
    return nil, "Failed to execute hash command: " .. command
  end

  local result = handle:read("*a")
  handle:close()

  if not result or result == "" then
    return nil, "Hash command produced no output."
  end

  local hash
  if os_type == "unix" then
    hash = result:match("^(%x+)") -- Extract hash from sha512sum output
  else -- windows
    -- CertUtil output is multi-line, hash is usually on the second line
    hash = result:match("\n(%x+)%s*\n")
    if hash then
      hash = hash:gsub("%s", "") -- Remove spaces if any
    end
  end

  if hash then
    return hash:lower()
  else
    return nil, "Could not parse hash from command output: " .. result
  end
end

return {
  extract_github_hash = extract_github_hash,
  hash_dependency = hash_dependency,
  calculate_sha512 = calculate_sha512,
}
