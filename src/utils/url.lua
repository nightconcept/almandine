--[[
  URL Utilities

  Provides functions for manipulating and normalizing URLs.
]]

local M = {}

---
-- Normalize GitHub URLs, separating base URL from commit hash and providing a raw download URL.
-- Handles blob URLs, raw URLs, and URLs with/without commit hashes.
-- @param url string The URL to normalize or reconstruct.
-- @param commit_hash_override string|nil Optional commit hash to use instead of one parsed from the URL.
-- @return string|nil base_url The base URL without the commit hash/ref.
--                        (e.g., https://github.com/user/repo/blob/main/file.lua). Nil on error.
-- @return string|nil ref The reference found in the URL (branch, tag, or commit hash). Nil if not applicable.
-- @return string|nil commit_hash The commit hash ONLY if the ref is a valid commit hash. Nil otherwise.
-- @return string|nil download_url The URL suitable for downloading raw content. Nil on error.
-- @return string|nil error_message Error message if normalization fails.
function M.normalize_github_url(url, commit_hash_override)
  if type(url) ~= "string" then
    return nil, nil, nil, nil, "URL must be a string."
  end

  local base_url, ref, commit_hash, download_url

  -- Pattern 1: GitHub Blob URL (potentially with commit hash override)
  local user, repo, blob_ref, path = url:match("^https://github%.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)$")
  if user then
    ref = commit_hash_override or blob_ref -- Store the actual ref
    base_url = string.format("https://github.com/%s/%s/blob/%s/%s", user, repo, ref, path)
    -- Check if the ref IS a commit hash
    if ref:match("^[a-fA-F0-9]{40}$") then
      commit_hash = ref
    else
      commit_hash = nil -- It's a branch or tag
    end
    -- Use the actual ref (branch/tag/hash) for the download URL
    download_url = string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", user, repo, ref, path)
    return base_url, ref, commit_hash, download_url, nil
  end

  -- Pattern 2: GitHub Raw URL (potentially with commit hash override)
  local user_raw, repo_raw, raw_ref, path_raw =
    url:match("^https://raw%.githubusercontent%.com/([^/]+)/([^/]+)/([^/]+)/(.+)$")
  if user_raw then
    ref = commit_hash_override or raw_ref -- Store the actual ref
    -- Reconstruct base_url using the ref
    base_url = string.format("https://github.com/%s/%s/blob/%s/%s", user_raw, repo_raw, ref, path_raw)
    -- Check if the ref IS a commit hash
    if ref:match("^[a-fA-F0-9]{40}$") then
      commit_hash = ref
    else
      commit_hash = nil -- It's a branch or tag
    end
    -- Use the actual ref for the download URL
    download_url =
      string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", user_raw, repo_raw, ref, path_raw)
    return base_url, ref, commit_hash, download_url, nil
  end

  -- Pattern 3: GitHub Gist Raw URL (Gists don't have the same base/commit structure)
  if url:match("^https://gist%.githubusercontent%.com/") then
    -- Gists are treated as opaque URLs; no base/commit separation possible.
    base_url = url
    commit_hash = nil -- Gists identify revisions differently
    ref = nil -- No ref concept here
    download_url = url
    return base_url, ref, commit_hash, download_url, nil
  end

  -- Pattern 4: GitHub URL without /blob/ part (e.g., link to repo root or non-code file view) - No directly download
  if url:match("^https://github%.com/") then
    -- Cannot reliably determine download URL or commit hash structure
    return url, nil, nil, nil, "URL points to a GitHub page, not a specific file blob/raw content."
  end

  -- Pattern 5: Non-GitHub URL - Assume it's directly downloadable
  base_url = url
  commit_hash = nil -- No GitHub commit concept
  ref = nil -- No ref concept here
  download_url = url
  return base_url, ref, commit_hash, download_url, nil
end

---
-- Create a standardized source identifier string for GitHub URLs.
-- Handles blob and raw URLs.
-- @param url string The GitHub URL to process.
-- @return string|nil identifier The formatted identifier (e.g., "github:user/repo/path/file.lua@ref"). Nil if not a recognized GitHub file URL.
-- @return string|nil error_message Error message if processing fails.
function M.create_github_source_identifier(url)
  if type(url) ~= "string" then
    return nil, "URL must be a string."
  end

  -- Pattern 1: GitHub Blob URL
  local user, repo, ref, path = url:match("^https://github%.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)$")
  if user then
    local identifier = string.format("github:%s/%s/%s@%s", user, repo, path, ref)
    return identifier, nil
  end

  -- Pattern 2: GitHub Raw URL
  local user_raw, repo_raw, ref_raw, path_raw =
    url:match("^https://raw%.githubusercontent%.com/([^/]+)/([^/]+)/([^/]+)/(.+)$")
  if user_raw then
    local identifier = string.format("github:%s/%s/%s@%s", user_raw, repo_raw, path_raw, ref_raw)
    return identifier, nil
  end

  -- Not a recognized GitHub file URL format for generating this specific identifier
  return nil, "URL is not a recognized GitHub blob/raw file URL format."

end

return M
