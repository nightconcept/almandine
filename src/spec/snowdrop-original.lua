#!/usr/bin/env lua

-- Simple Lua script to manage single-file dependencies from GitHub
-- Downloads files only if they are missing or have changed upstream.
-- Relies on the 'curl' command-line tool.

local dependencies = {
  -- Format: { url = "raw_github_url", path = "local/path/to/save" }
  {
    url = "https://raw.githubusercontent.com/Oval-Tutu/shove/main/shove.lua",
    path = "src/spec/shove.lua"
  },
  {
    url = "https://raw.githubusercontent.com/Oval-Tutu/shove/main/shove-profiler.lua",
    path = "src/spec/shove-profiler.lua"
  },
  {
    url = "https://raw.githubusercontent.com/mdqinc/SDL_GameControllerDB/master/gamecontrollerdb.txt",
    path = "src/spec/gamecontrollerdb.txt"
  },
  -- Add more dependencies here
}

local manifest_file = "deps_manifest.lua"

-- <<< CODE TO LOAD MANIFEST START >>>
-- Initialize manifest as an empty table by default
local manifest = {}

-- Attempt to load the existing manifest file safely
-- Using loadfile is generally safer than dofile as it compiles without executing immediately
-- and allows us to run it in a controlled environment.
local loader, load_err = loadfile(manifest_file)

if loader then
    -- Successfully loaded the file chunk. Now execute it.
    -- For Lua 5.1 (which you seem to be using based on the path), use setfenv
    -- to run the chunk in a specific environment table.
    -- This prevents the manifest file from polluting the global namespace
    -- and allows us to capture the 'manifest' table it defines.
    local env = {} -- Create an empty environment for the chunk
    setfenv(loader, env) -- Set the chunk's environment to our table
    local ok, exec_err = pcall(loader) -- Execute the chunk safely

    if ok then
        -- Execution succeeded. Check if it defined the 'manifest' table in its environment.
        if env.manifest and type(env.manifest) == "table" then
            manifest = env.manifest -- Assign the loaded table to our local variable
            print("Loaded existing manifest from " .. manifest_file)
        else
            print("Warning: Manifest file '" .. manifest_file .. "' executed but did not define 'manifest' table correctly. Starting fresh.")
            -- manifest remains {}
        end
    else
        -- Execution failed (e.g., syntax error in the manifest file)
        print("Warning: Error executing manifest file '" .. manifest_file .. "': " .. tostring(exec_err))
        print("Starting with an empty manifest.")
        -- manifest remains {}
    end
else
    -- loadfile failed. Check if it was because the file doesn't exist (common)
    -- or another error (permissions, etc.).
    -- Handle potential variations in Lua 5.1 error messages for file not found
    local is_not_found = false
    if load_err then
      if load_err:match("cannot open .* No such file or directory") then is_not_found = true end
      if load_err:match("cannot open '"..manifest_file.."'") then is_not_found = true end -- Another common pattern
    end

    if load_err and not is_not_found then
        -- Error other than file not found
        print("Warning: Error loading manifest file '" .. manifest_file .. "': " .. tostring(load_err))
    else
        -- File likely doesn't exist (or basic open error)
        print("Manifest file '" .. manifest_file .. "' not found or could not be opened. Starting fresh.")
    end
    -- manifest remains {} in case of any load error
end
-- <<< CODE TO LOAD MANIFEST END >>>


-- Helper function to run shell commands
local function run_command(cmd)
  -- print("Executing:", cmd) -- Uncomment for debugging
  local pipe = assert(io.popen(cmd .. " 2>&1", "r")) -- Capture stdout and stderr
  local output = assert(pipe:read("*a"))
  pipe:close()
  -- Note: io.popen doesn't reliably return exit codes cross-platform.
  -- For robust error checking, os.execute might be better, but capturing output is harder.
  -- Or use a Lua library that handles processes better.
  return output
end

-- Helper function to ensure directory exists (like mkdir -p)
-- WARNING: Simple version using os.execute, potentially insecure/platform-dependent.
-- Using a library like LuaFileSystem (lfs.mkdir) is recommended for robust code.
local function ensure_dir(path)
  -- Extract directory part (handles both / and \ separators)
  local dir = path:match("^(.*[/\\])")
  if dir and dir ~= "" and dir ~= "./" and dir ~= ".\\" then
    -- Check OS using standard Lua 'package.config' which holds the directory separator ('\' or '/')
    -- as its first character.
    local is_windows = package.config:sub(1,1) == '\\'

    -- Construct the appropriate command
    local cmd
    if is_windows then
      -- Windows: Use 'mkdir' but check existence first to avoid errors if it exists.
      -- Replace forward slashes with backslashes for Windows cmd.
      local win_dir = dir:gsub('/', '\\')
      -- Ensure trailing backslash is removed if present, mkdir doesn't like it sometimes
      win_dir = win_dir:gsub("\\$", "")
      cmd = 'if not exist "' .. win_dir .. '" mkdir "' .. win_dir .. '"'
    else
      -- POSIX (Linux, macOS): Use 'mkdir -p' which handles intermediate directories
      -- and doesn't error if the directory already exists.
      local posix_dir = dir:gsub("\\", "/") -- Ensure forward slashes
       -- Ensure trailing slash is removed if present
      posix_dir = posix_dir:gsub("/$", "")
      cmd = 'mkdir -p "' .. posix_dir .. '"'
    end

    -- print("Executing mkdir command:", cmd) -- Uncomment for debugging
    local result = os.execute(cmd)
    -- os.execute might return true/false/nil/exitcode depending on OS/Lua version.
    -- This doesn't provide great error checking, but should work for basic cases.
    -- if result ~= 0 and result ~= true then print("Warning: mkdir command may have failed for:", dir) end
  end
end

-- Helper function to parse GitHub URL into components
-- Handles both raw.githubusercontent.com and github.com/blob/ URLs
local function parse_github_url(url)
  local owner, repo, branch, path
  -- Try matching raw.githubusercontent.com format
  owner, repo, branch, path = url:match("://raw%.githubusercontent%.com/([^/]+)/([^/]+)/([^/]+)/(.+)")
  if owner then
    return { owner = owner, repo = repo, branch = branch, path = path }
  end
  -- Try matching github.com/blob/ format
  owner, repo, branch, path = url:match("://github%.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)")
  if owner then
    -- Note: For blob URLs, the raw content URL is different.
    -- The get_github_file_meta function handles fetching the correct download URL via API.
    return { owner = owner, repo = repo, branch = branch, path = path }
  end
  print("Warning: URL format not recognized as raw.githubusercontent.com or github.com/blob/:", url)
  return nil -- URL format not recognized
end

-- Function to get file metadata (SHA, download URL) from GitHub API
-- Returns { sha = "...", download_url = "..." } or nil on error
local function get_github_file_meta(owner, repo, path, branch)
  -- Construct the GitHub API URL
  -- Using the ref parameter ensures we check the correct branch
  local api_url = string.format(
    "https://api.github.com/repos/%s/%s/contents/%s?ref=%s",
    owner, repo, path, branch
  )

  -- Make API request using curl
  -- -H "Accept: application/vnd.github.v3+json" is good practice
  -- WARNING: Unauthenticated requests have low rate limits (~60/hr per IP).
  -- For frequent use, add -H "Authorization: Bearer YOUR_GITHUB_TOKEN"
  local cmd = string.format(
    'curl -fsSL -H "Accept: application/vnd.github.v3+json" "%s"',
    api_url
  )
  local response_json = run_command(cmd)

  -- Basic check for curl errors (e.g., network issues, 404 Not Found)
  -- A zero-length response often indicates curl failed silently (-fsSL)
  if response_json == "" or response_json:match('"message": "Not Found"') then
    print(string.format("Error: Failed to get metadata for %s/%s path:'%s' branch:'%s' (check URL, branch, token, rate limits)", owner, repo, path, branch))
    if response_json ~= "" then print("GitHub API Response:", response_json) end
    return nil
  end

  -- Parse JSON to get sha and download_url
  -- WARNING: Using string patterns for JSON parsing is fragile!
  -- A proper JSON library (like lua-cjson) is strongly recommended.
  local sha = response_json:match('"sha":%s*"([^"]+)"')
  local download_url = response_json:match('"download_url":%s*"([^"]+)"')

  -- Check if the response was for a directory instead of a file
  if not download_url and response_json:match('"type":%s*"dir"') then
      print(string.format("Error: Path seems to be a directory, not a file: %s/%s:%s", owner, repo, path))
      return nil
  end

  if sha and download_url then
    return { sha = sha, download_url = download_url }
  else
    print("Error: Could not parse SHA or download_url from API response for:", path)
    print("Response snippet:", response_json:sub(1, 300)) -- Print part of the response for debugging
    return nil
  end
end

-- Function to download a file from a URL
local function download_file(url, target_path)
  print("Downloading " .. url .. " to " .. target_path)
  ensure_dir(target_path)
  -- Ensure quotes around paths, especially for Windows
  local cmd = string.format('curl -fsSL "%s" -o "%s"', url, target_path)
  local output = run_command(cmd)
  -- Basic check: See if the command seemed to succeed (no output often means success with -fsSL -o)
  -- A better check would be os.execute and checking the return code.
  -- Or checking if the file exists and has size > 0 afterwards.
  if output ~= "" then
      print("Warning: Potential issue downloading " .. target_path .. ": " .. output)
  end
  -- We'll assume success if curl didn't output errors due to -fsS
end

-- Process dependencies
local manifest_changed = false
for _, dep in ipairs(dependencies) do
  print("Processing dependency: " .. dep.path)

  -- Step 1: Parse URL
  local url_parts = parse_github_url(dep.url)

  -- Check if URL parsing was successful before proceeding
  if url_parts then

    -- Step 2: Get Meta (only if URL parsing succeeded)
    local meta = get_github_file_meta(url_parts.owner, url_parts.repo, url_parts.path, url_parts.branch)

    -- Check if getting metadata was successful before proceeding
    if meta then

      -- Step 3: Process Meta & Download (only if metadata succeeded)
      local current_sha = meta.sha
      local download_url = meta.download_url
      -- This access is now safe because 'manifest' is guaranteed to be a table
      local previous_sha = manifest[dep.path]

      -- Check if download is needed
      local needs_download = false
      local file_exists = false
      -- Use io.open to check file existence (works in Lua 5.1)
      local f_exists, open_err = io.open(dep.path, "r")
      if f_exists then
          file_exists = true
          f_exists:close()
      end

      if not file_exists then
        print("Local file missing.")
        needs_download = true
      elseif current_sha ~= previous_sha then
        print(string.format("SHA changed: %s -> %s", previous_sha or "none", current_sha))
        needs_download = true
      else
        -- Use string.sub for Lua 5.1 compatibility if needed (sub is standard)
        print("Local file exists and SHA matches (" .. string.sub(current_sha, 1, 7) .. "). No download needed.")
      end

      -- Download if needed
      if needs_download then
        download_file(download_url, dep.path)
        -- Update the local manifest table
        manifest[dep.path] = current_sha
        manifest_changed = true
      end
      -- End of main logic for this dependency

    else
      -- This block runs if get_github_file_meta failed
      print("Skipping download due to error fetching metadata.")
    end -- End 'if meta' block

  else
    -- This block runs if parse_github_url failed
    print("Error: Could not parse GitHub URL:", dep.url)
    -- No need to explicitly continue, loop will proceed to next dependency
  end -- End 'if url_parts' block

end -- End of the for loop

-- Save the updated manifest if changes were made
if manifest_changed then
  print("Saving updated manifest to " .. manifest_file)
  -- Use 'w' mode to overwrite the file completely
  local file, save_err = io.open(manifest_file, "w")
  if not file then
      print("Error: Could not open manifest file '"..manifest_file.."' for writing: " .. tostring(save_err))
  else
      -- IMPORTANT: Write the file so it can be loaded correctly next time by the loader code.
      -- It needs to define the 'manifest' variable within its environment.
      file:write("-- Dependency Manifest (automatically generated)\n")
      file:write("manifest = {\n") -- Assign to the 'manifest' variable
      -- Sort keys for consistent output (optional but nice)
      local sorted_paths = {}
      for path in pairs(manifest) do table.insert(sorted_paths, path) end
      table.sort(sorted_paths)
      for _, path in ipairs(sorted_paths) do
          local sha = manifest[path]
          -- Escape backslashes in paths for Windows compatibility within Lua string
          local escaped_path = path:gsub("\\", "\\\\")
          file:write(string.format('  ["%s"] = "%s",\n', escaped_path, sha))
      end
      file:write("}\n")
      file:close()
  end
else
    print("No changes detected, manifest not updated.")
end

print("Dependency management complete.")