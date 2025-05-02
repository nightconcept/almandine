--[[
  URL Utilities
  Provides functions for manipulating and normalizing URLs, primarily for GitHub sources.
]]

local M = {}

---
-- Normalize GitHub URLs, separating base URL from ref/commit and providing a raw download URL.
-- Handles blob URLs, raw URLs, and optionally overrides the ref/commit.
-- For non-GitHub URLs, it returns the original URL as base and download URL.
-- @param url string The URL to normalize.
-- @param commit_hash_override string|nil Optional commit hash/ref to force into the URLs.
-- @return string|nil base_url The conceptual base URL (e.g., GitHub blob URL format). Nil on error.
-- @return string|nil ref The branch, tag, or commit hash found or used.
-- @return string|nil commit_hash The commit hash if the ref is a 40-char hex string. Nil otherwise.
-- @return string|nil download_url The direct download URL (e.g., raw.githubusercontent). Nil on error.
-- @return string|nil error_message Description of error if normalization fails.
function M.normalize_github_url(url, commit_hash_override)
  if type(url) ~= "string" then
    return nil, nil, nil, nil, "URL must be a string."
  end

  local base_url, ref, commit_hash, download_url

  -- Pattern 1: GitHub Blob URL
  local user, repo, blob_ref, path = url:match("^https://github%.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)$")
  if user then
    ref = commit_hash_override or blob_ref -- Use override if present
    base_url = string.format("https://github.com/%s/%s/blob/%s/%s", user, repo, ref, path)
    -- Check if the effective ref is a commit hash
    -- Ugly, but let's try explicit repetition to rule out quantifier issues
    local explicit_pattern = "^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$"
    local match_result = ref:match(explicit_pattern)
    if match_result then
      commit_hash = ref -- Assign to the function-scope commit_hash
    end
    download_url = string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", user, repo, ref, path)
    return base_url, ref, commit_hash, download_url, nil
  end

  -- Pattern 2: GitHub Raw URL
  local user_raw, repo_raw, raw_ref, path_raw =
    url:match("^https://raw%.githubusercontent%.com/([^/]+)/([^/]+)/([^/]+)/(.+)$")
  if user_raw then
    ref = commit_hash_override or raw_ref -- Use override if present
    base_url = string.format("https://github.com/%s/%s/blob/%s/%s", user_raw, repo_raw, ref, path_raw)
    -- Check if the effective ref is a commit hash
    -- Ugly, but let's try explicit repetition to rule out quantifier issues
    local explicit_pattern_raw = "^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$"
    local match_result_raw = ref:match(explicit_pattern_raw)
    if match_result_raw then
      commit_hash = ref -- Assign to the function-scope commit_hash
    end
    download_url =
      string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", user_raw, repo_raw, ref, path_raw)
    return base_url, ref, commit_hash, download_url, nil
  end

  -- Pattern 3: GitHub Gist Raw URL
  if url:match("^https://gist%.githubusercontent%.com/") then
    -- Gists have a different structure, treat as opaque download URL.
    -- No standard base URL or separate ref/commit concept here.
    base_url = url -- Use the input URL itself as the 'base'
    ref = nil
    commit_hash = nil
    download_url = url
    return base_url, ref, commit_hash, download_url, nil
  end

  -- Pattern 4: GitHub URL that isn't a blob/raw file link (e.g., repo root)
  if url:match("^https://github%.com/") then
    -- Cannot determine a direct file download URL.
    return url, nil, nil, nil, "URL points to a GitHub page, not a specific file blob/raw content."
  end

  -- Pattern 5: Non-GitHub URL
  -- Assume it's directly downloadable.
  base_url = url
  ref = nil
  commit_hash = nil
  download_url = url
  return base_url, ref, commit_hash, download_url, nil
end

---
-- Create a standardized source identifier string for GitHub URLs (`github:user/repo/path@ref`).
-- @param url string The GitHub URL (blob or raw) to process.
-- @return string|nil identifier The formatted identifier string. Nil if not a recognized GitHub file URL.
-- @return string|nil error_message Description of error if processing fails.
function M.create_github_source_identifier(url)
  if type(url) ~= "string" then
    return nil, "URL must be a string."
  end

  -- Pattern 1: GitHub Blob URL
  local user, repo, ref, path = url:match("^https://github%.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)$")
  if user then
    return string.format("github:%s/%s/%s@%s", user, repo, path, ref), nil
  end

  -- Pattern 2: GitHub Raw URL
  local user_raw, repo_raw, ref_raw, path_raw =
    url:match("^https://raw%.githubusercontent%.com/([^/]+)/([^/]+)/([^/]+)/(.+)$")
  if user_raw then
    return string.format("github:%s/%s/%s@%s", user_raw, repo_raw, path_raw, ref_raw), nil
  end

  -- Not a recognized format for this specific identifier type.
  return nil, "URL is not a recognized GitHub blob or raw file URL format."
end

return M
