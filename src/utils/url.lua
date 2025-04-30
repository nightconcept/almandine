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
-- @return string|nil base_url The base URL without the commit hash.
--                        (e.g., https://github.com/user/repo/blob/main/file.lua). Nil on error.
-- @return string|nil commit_hash The commit hash found in the URL or the override. Nil if no hash applicable/found.
-- @return string|nil download_url The URL suitable for downloading raw content. Nil on error.
-- @return string|nil error_message Error message if normalization fails.
function M.normalize_github_url(url, commit_hash_override)
  if type(url) ~= "string" then
    return nil, nil, nil, "URL must be a string."
  end

  local base_url, commit_hash, download_url

  -- Pattern 1: GitHub Blob URL (potentially with commit hash override)
  local user, repo, blob_ref, path = url:match("^https://github%.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)$")
  if user then
    commit_hash = commit_hash_override or blob_ref
    -- Keep original ref in base_url
    base_url = string.format("https://github.com/%s/%s/blob/%s/%s", user, repo, blob_ref, path)
    download_url = string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", user, repo, commit_hash, path)
    return base_url, commit_hash, download_url, nil
  end

  -- Pattern 2: GitHub Raw URL (potentially with commit hash override)
  local user_raw, repo_raw, raw_ref, path_raw =
    url:match("^https://raw%.githubusercontent%.com/([^/]+)/([^/]+)/([^/]+)/(.+)$")
  if user_raw then
    commit_hash = commit_hash_override or raw_ref
    -- Attempt to reconstruct a somewhat canonical "source" URL (blob style), keep original ref in base
    base_url = string.format("https://github.com/%s/%s/blob/%s/%s", user_raw, repo_raw, raw_ref, path_raw)
    download_url =
      string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", user_raw, repo_raw, commit_hash, path_raw)
    return base_url, commit_hash, download_url, nil
  end

  -- Pattern 3: GitHub Gist Raw URL (Gists don't have the same base/commit structure)
  if url:match("^https://gist%.githubusercontent%.com/") then
    -- Gists are treated as opaque URLs; no base/commit separation possible.
    base_url = url
    commit_hash = nil -- Gists identify revisions differently
    download_url = url
    return base_url, commit_hash, download_url, nil
  end

  -- Pattern 4: GitHub URL without /blob/ part (e.g., link to repo root or non-code file view) - No directly download
  if url:match("^https://github%.com/") then
    -- Cannot reliably determine download URL or commit hash structure
    return url, nil, nil, "URL points to a GitHub page, not a specific file blob/raw content."
  end

  -- Pattern 5: Non-GitHub URL - Assume it's directly downloadable
  base_url = url
  commit_hash = nil -- No GitHub commit concept
  download_url = url
  return base_url, commit_hash, download_url, nil
end

return M
