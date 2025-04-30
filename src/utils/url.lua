--[[
  URL Utilities

  Provides functions for manipulating and normalizing URLs.
]]

local M = {}

---
-- Normalize GitHub URLs by converting blob URLs to raw URLs.
-- @param url string The URL to normalize
-- @return string source_url The original or normalized source URL (for storing in manifest).
-- @return string download_url The URL suitable for downloading (raw content).
-- @return string? error_message Error message if normalization fails.
function M.normalize_github_url(url)
  if type(url) ~= "string" then
    return nil, nil, "URL must be a string."
  end

  -- Check if this is a GitHub blob URL
  local username, repo, commit, path = url:match("^https://github%.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)$")
  if username then -- Match successful
    -- Convert to raw URL for downloading
    local raw_url = string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", username, repo, commit, path)
    -- Return the original blob URL as the source_url and the raw_url for download
    return url, raw_url
  end

  -- Check if it might already be a raw URL (or other downloadable URL)
  if url:match("^https://raw%.githubusercontent%.com/") or url:match("^https://gist%.githubusercontent%.com/") then
    -- Assume it's already suitable for download, return it for both
    return url, url
  end

  -- If not a recognizable GitHub URL pattern, return the original URL for both
  -- We assume it might be a direct download link from another source.
  return url, url
end

return M
