-- E2E Test Scaffolding Helpers
-- Provides functions to create isolated test environments (sandboxes),
-- run almd commands within them, and interact with project files.

local scaffold = {}

-- Attempt to load LuaFileSystem, but don't error if it's not present
local has_lfs, lfs = pcall(require, "lfs")

-- --- Private Helper Functions ---

-- Simple platform detection
local function is_windows()
  return package.config:sub(1, 1) == "\\"
end

-- Creates a directory path, including parent directories if they don't exist.
-- Uses lfs if available, otherwise uses os.execute.
local function mkdir_p(path)
  if has_lfs then
    -- lfs.mkdir handles creating parent directories implicitly if the path exists
    -- up to the last component. We need to create them iteratively.
    local current_path = ""
    for part in path:gmatch("([^" .. (is_windows() and "\\" or "/") .. "]+)") do
      current_path = current_path .. part .. (is_windows() and "\\" or "/")
      local mode = lfs.attributes(current_path, "mode")
      if not mode then
        local ok, err = lfs.mkdir(current_path)
        if not ok then
          return false, "Failed to create directory '" .. current_path .. "': " .. err
        end
      elseif mode ~= "directory" then
        return false, "Path component '" .. current_path .. "' exists but is not a directory"
      end
    end
    return true
  else
    -- Fallback using os.execute (less robust, relies on shell commands)
    local command
    if is_windows() then
      -- Windows `mkdir` doesn't have a simple `-p`. We'll try anyway, it might work on newer systems/shells.
      -- A more robust solution would involve iteratively checking and creating each part.
      command = 'mkdir "' .. path .. '"' -- Basic attempt
    else
      command = 'mkdir -p "' .. path .. '"'
    end
    local success = os.execute(command)
    if success == 0 or success == true then -- os.execute returns true on success on some systems, 0 on others
      return true
    else
      -- Attempt to suppress output might fail, but try anyway
      os.execute(command .. (is_windows() and " > nul 2>&1" or " > /dev/null 2>&1"))
      -- Check again if it exists now (maybe it failed because it already existed)
      local f = io.open(path) -- This is not a perfect check for a directory, but a basic fallback
      if f then
        f:close()
        -- Attempt to determine if it's a directory (crude check)
        local check_cmd = is_windows() and 'if exist "' .. path .. '\\" echo 1' or 'test -d "' .. path .. '" && echo 1'
        local handle = io.popen(check_cmd)
        local result = handle and handle:read("*a")
        if handle then
          handle:close()
        end
        if result and result:match("1") then
          return true
        end -- Likely a directory
      end
      return false, "Failed to create directory '" .. path .. "' using os.execute (code: " .. tostring(success) .. ")"
    end
  end
end

-- Recursively removes a directory and its contents.
-- Uses lfs if available, otherwise uses os.execute.
local function rmdir_recursive(path)
  if not path or path == "/" or path == "." or path == ".." then
    return false, "Invalid or dangerous path for recursive removal: " .. tostring(path)
  end

  if has_lfs then
    -- lfs doesn't have a built-in recursive remove, need to implement it
    local function rm_contents(dir)
      for entry in lfs.dir(dir) do
        if entry ~= "." and entry ~= ".." then
          local full_path = dir .. (is_windows() and "\\" or "/") .. entry
          local mode = lfs.attributes(full_path, "mode")
          if mode == "directory" then
            local ok, err = rm_contents(full_path) -- Recurse into subdirectory
            if not ok then
              return false, err
            end
            local removed, rmerr = lfs.rmdir(full_path)
            if not removed then
              return false, "Failed to remove directory '" .. full_path .. "': " .. rmerr
            end
          elseif mode == "file" then
            local removed, rmerr = os.remove(full_path) -- os.remove works for files
            if not removed then
              return false, "Failed to remove file '" .. full_path .. "': " .. rmerr
            end
          else
            -- Handle other types like symlinks if necessary, or ignore/error
            -- For now, we'll error if we encounter unexpected types
            return false, "Cannot remove entry '" .. full_path .. "' of unknown type: " .. tostring(mode)
          end
        end
      end
      return true -- Successfully cleared contents
    end
    -- First, remove contents
    local cleared, clear_err = rm_contents(path)
    if not cleared then
      return false, clear_err
    end
    -- Then, remove the now-empty directory
    local removed, rmerr = lfs.rmdir(path)
    if not removed then
      return false, "Failed to remove directory '" .. path .. "': " .. rmerr
    end
    return true
  else
    -- Fallback using os.execute (relies on shell commands)
    local command
    if is_windows() then
      -- Check if directory exists before attempting removal
      local check_cmd = 'if exist "' .. path .. '\\" (echo 1)'
      local handle_check = io.popen(check_cmd)
      local exists = handle_check and handle_check:read("*a")
      if handle_check then
        handle_check:close()
      end
      if not exists or not exists:match("1") then
        return true
      end -- Already gone or doesn't exist

      command = 'rmdir /s /q "' .. path .. '"'
    else
      -- Check if directory exists before attempting removal
      local check_cmd = 'test -d "' .. path .. '" && echo 1'
      local handle_check = io.popen(check_cmd)
      local exists = handle_check and handle_check:read("*a")
      if handle_check then
        handle_check:close()
      end
      if not exists or not exists:match("1") then
        return true
      end -- Already gone or doesn't exist

      command = 'rm -rf "' .. path .. '"'
    end
    local success = os.execute(command)
    -- Check if removal was successful (directory should no longer exist)
    local f_check = io.open(path)
    if f_check then
      f_check:close()
      -- If it still exists, removal failed
      return false, "Failed to remove directory '" .. path .. "' using os.execute (code: " .. tostring(success) .. ")"
    end
    return true -- Directory no longer exists
  end
end

-- --- Public Scaffold Functions ---

-- Creates a unique temporary sandbox directory for a test.
-- Returns the absolute path to the sandbox and a cleanup function.
function scaffold.create_sandbox_project()
  -- Create sandboxes in a sub-directory of the project for easier management/cleanup
  local base_sandbox_dir = "_test_sandboxes"
  local ok, err = mkdir_p(base_sandbox_dir)
  if not ok then
    return nil, nil, "Failed to create base sandbox directory '" .. base_sandbox_dir .. "': " .. err
  end

  -- Generate a unique directory name using time and random number
  local timestamp = os.time()
  local random_num = math.random(1000, 9999)
  local sandbox_name = string.format("sandbox_%d_%d", timestamp, random_num)
  local sandbox_path = base_sandbox_dir .. (is_windows() and "\\" or "/") .. sandbox_name

  ok, err = mkdir_p(sandbox_path)
  if not ok then
    return nil, nil, "Failed to create unique sandbox directory '" .. sandbox_path .. "': " .. err
  end

  local absolute_sandbox_path
  if has_lfs then
    absolute_sandbox_path = lfs.currentdir() .. (is_windows() and "\\" or "/") .. sandbox_path
  else
    -- Try to get current directory using os.execute (less reliable)
    local cwd_cmd = is_windows() and "cd" or "pwd"
    local handle = io.popen(cwd_cmd)
    local cwd = handle and handle:read("*a"):gsub("^%s*", ""):gsub("%s*$", "") -- Trim whitespace
    if handle then
      handle:close()
    end
    if cwd and cwd ~= "" then
      absolute_sandbox_path = cwd .. (is_windows() and "\\" or "/") .. sandbox_path
    else
      -- Fallback to relative path if cwd fails
      absolute_sandbox_path = sandbox_path
      print("Warning: Could not determine absolute path for sandbox. Using relative path: " .. sandbox_path)
    end
  end

  local cleanup_func = function()
    local removed, remove_err = rmdir_recursive(sandbox_path)
    if not removed then
      print("Warning: Failed to clean up sandbox directory '" .. sandbox_path .. "': " .. tostring(remove_err))
      -- Consider adding more robust retry or error reporting here if needed
    end
  end

  return absolute_sandbox_path, cleanup_func
end

-- Creates a basic project.lua file in the sandbox directory.
-- initial_data should be a Lua table representing the project structure.
function scaffold.init_project_file(sandbox_path, initial_data)
  initial_data = initial_data or { name = "test-project", version = "0.1.0", dependencies = {} }
  local project_file_path = sandbox_path .. (is_windows() and "\\" or "/") .. "project.lua"

  -- Basic serialization (not robust for all Lua types, e.g., functions, cycles)
  local function serialize(tbl, indent)
    indent = indent or ""
    local lines = { "{" }
    for k, v in pairs(tbl) do
      local key_str = nil
      if type(k) == "string" then
        -- Check if key needs quoting (e.g., contains spaces or special chars)
        if k:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then
          key_str = k
        else
          key_str = string.format('["%s"]', k:gsub('"', '\\"'):gsub("\\", "\\\\"))
        end
      elseif type(k) == "number" then
        key_str = string.format("[%d]", k)
      end

      -- Only proceed if the key is valid (string or number)
      if key_str then
        local value_str = nil
        if type(v) == "string" then
          value_str = string.format('"%s"', v:gsub('"', '\\"'):gsub("\\", "\\\\"))
        elseif type(v) == "number" or type(v) == "boolean" then
          value_str = tostring(v)
        elseif type(v) == "table" then
          value_str = serialize(v, indent .. "  ") -- Recurse for nested tables
        end

        -- Only insert if the value is serializable (string, number, boolean, table)
        if value_str then
          table.insert(lines, string.format("%s  %s = %s,", indent, key_str, value_str))
        end
        -- If value_str is nil (other type), we skip inserting this key-value pair
      end
      -- If key_str is nil (other type), we skip inserting this key-value pair
    end
    table.insert(lines, indent .. "}")
    return table.concat(lines, "\n")
  end

  local content = "return " .. serialize(initial_data)

  local file, err = io.open(project_file_path, "w")
  if not file then
    return false, "Failed to open project file '" .. project_file_path .. "' for writing: " .. tostring(err)
  end
  local wrote, write_err = file:write(content)
  file:close() -- Ensure file is closed even if write failed

  if not wrote then
    return false, "Failed to write to project file '" .. project_file_path .. "': " .. tostring(write_err)
  end

  return true, project_file_path
end

-- Reads the content of a text file.
local function read_text_file(path)
  local file, err = io.open(path, "r")
  if not file then
    return nil, "Failed to open file '" .. path .. "' for reading: " .. tostring(err)
  end
  local content = file:read("*a")
  file:close()
  return content
end

-- Executes the almd command targeting the sandbox directory using os.execute for reliable exit code.
-- Captures output via temporary files.
-- args_table should be a list of command-line arguments (e.g., {"add", "url", "-d", "path"})
-- Returns success (boolean), stdout (string), stderr (string).
function scaffold.run_almd(sandbox_path, args_table)
  -- LFS is required for chdir and reliable path manipulation
  if not has_lfs then
    return false, "", "Error: LuaFileSystem (lfs) is required for robust sandbox testing but not found."
  end

  -- Determine absolute path to main.lua
  local absolute_main_script_path = lfs.currentdir() .. (is_windows() and "\\src\\main.lua" or "/src/main.lua")

  -- Check if main script exists
  if not scaffold.file_exists(absolute_main_script_path) then
    return false, "", "Error: main.lua script not found at calculated path: " .. absolute_main_script_path
  end

  -- Construct the argument string, ensuring proper quoting
  local args_string = ""
  if #args_table > 0 then
    local quoted_args = {}
    for _, arg in ipairs(args_table) do
      table.insert(quoted_args, '"' .. tostring(arg):gsub('"', '\\"') .. '"')
    end
    args_string = table.concat(quoted_args, " ")
  end

  -- Generate unique temporary file names within the sandbox
  local timestamp = os.time()
  local random_num = math.random(10000, 99999)
  local tmp_stdout_name = string.format("_tmp_stdout_%d_%d.txt", timestamp, random_num)
  local tmp_stderr_name = string.format("_tmp_stderr_%d_%d.txt", timestamp, random_num)
  -- Use absolute paths for the temp files inside the sandbox
  local tmp_stdout_path = sandbox_path .. (is_windows() and "\\" or "/") .. tmp_stdout_name
  local tmp_stderr_path = sandbox_path .. (is_windows() and "\\" or "/") .. tmp_stderr_name

  -- Construct the command with redirection
  local lua_exec = 'lua "' .. absolute_main_script_path .. '" ' .. args_string
  local redirect_stdout = '> "' .. tmp_stdout_path .. '"'
  local redirect_stderr
  if is_windows() then
    redirect_stderr = '2> "' .. tmp_stderr_path .. '"'
  else
    -- POSIX: 2>&1 redirects stderr to wherever stdout is going (the file)
    -- However, simpler might be redirecting separately if combined output isn't needed
    redirect_stderr = '2> "' .. tmp_stderr_path .. '"'
  end
  local command = lua_exec .. " " .. redirect_stdout .. " " .. redirect_stderr

  -- Change directory into sandbox
  local original_dir = lfs.currentdir()
  local chdir_ok, chdir_err = pcall(lfs.chdir, sandbox_path)
  if not chdir_ok then
    return false, "", "Failed to chdir into sandbox '" .. sandbox_path .. "': " .. tostring(chdir_err)
  end

  -- Execute using os.execute
  local exec_result = os.execute(command)

  -- Change back to original directory immediately after execution
  local chback_ok, chback_err = pcall(lfs.chdir, original_dir)
  if not chback_ok then
    print("Warning: Failed to chdir back to original directory '" .. original_dir .. "': " .. tostring(chback_err))
    -- Continue, but state might be affected for subsequent tests if cleanup fails
  end

  -- Determine success based on os.execute result (platform-dependent)
  local is_success
  if is_windows() then
    is_success = (exec_result == true) -- Windows os.execute returns boolean
  else
    is_success = (exec_result == 0) -- POSIX os.execute returns exit code (0 for success)
  end

  -- Read output from temp files
  local stdout_content, stdout_err = read_text_file(tmp_stdout_path)
  local stderr_content, stderr_err = read_text_file(tmp_stderr_path)

  -- Clean up temp files
  os.remove(tmp_stdout_path)
  os.remove(tmp_stderr_path)

  -- Combine outputs for simplicity? Or return separately?
  -- For now, let's combine them similar to previous behavior.
  local combined_output = (stdout_content or "") .. (stderr_content or "")
  if stdout_err then
    combined_output = combined_output .. "\nError reading stdout temp file: " .. stdout_err
  end
  if stderr_err then
    combined_output = combined_output .. "\nError reading stderr temp file: " .. stderr_err
  end

  return is_success, combined_output, "" -- Return combined output as stdout, empty stderr
end

-- Checks if a file or directory exists at the given absolute or relative path.
function scaffold.file_exists(path)
  if has_lfs then
    return lfs.attributes(path, "mode") ~= nil
  else
    -- Fallback using io.open
    local file = io.open(path, "r")
    if file then
      file:close()
      return true
    else
      -- io.open fails for directories on some systems, try os.execute based check
      local check_cmd = is_windows() and 'if exist "' .. path .. '" (echo 1)' or 'test -e "' .. path .. '" && echo 1'
      local handle = io.popen(check_cmd)
      local result = handle and handle:read("*a")
      if handle then
        handle:close()
      end
      return result and result:match("1") ~= nil
    end
  end
end

-- Reads and parses a Lua file (like project.lua or almd-lock.lua).
-- Returns the loaded Lua table/value, or nil and an error message.
local function read_lua_file(file_path)
  if not scaffold.file_exists(file_path) then
    return nil, "File not found: " .. file_path
  end

  -- loadfile executes the file in an empty environment by default, which is good
  local func, load_err = loadfile(file_path)
  if not func then
    return nil, "Failed to load file '" .. file_path .. "': " .. tostring(load_err)
  end

  -- Execute the loaded chunk
  local success, result_or_err = pcall(func)
  if not success then
    return nil, "Failed to execute file '" .. file_path .. "' content: " .. tostring(result_or_err)
  end

  -- Check if the file returned a table (as expected for config files)
  if type(result_or_err) ~= "table" then
    -- Allow nil return for empty/non-returning files, but warn?
    if result_or_err == nil then
      return {}, nil -- Return empty table if file returns nothing explicitly
    end
    -- Error if it returns something other than a table or nil
    return nil, "File '" .. file_path .. "' did not return a table (returned " .. type(result_or_err) .. ")"
  end

  return result_or_err, nil -- Return the table and no error
end

-- Reads and parses the project.lua file from the sandbox.
function scaffold.read_project_lua(sandbox_path)
  local project_file_path = sandbox_path .. (is_windows() and "\\" or "/") .. "project.lua"
  return read_lua_file(project_file_path)
end

-- Reads and parses the almd-lock.lua file from the sandbox.
function scaffold.read_lock_lua(sandbox_path)
  local lock_file_path = sandbox_path .. (is_windows() and "\\" or "/") .. "almd-lock.lua"
  return read_lua_file(lock_file_path)
end

-- Reads the content of a file. Returns the content as a string, or nil and an error message.
function scaffold.read_file(file_path)
  if not scaffold.file_exists(file_path) then
    return nil, "File not found: " .. file_path
  end
  local file, err = io.open(file_path, "r")
  if not file then
    return nil, "Failed to open file '" .. file_path .. "' for reading: " .. tostring(err)
  end
  local content, read_err = file:read("*a") -- Read the whole file
  file:close()
  if content == nil then -- Check if read failed
    -- Manually concatenate the error message to avoid long line
    local error_message = "Failed to read file '" .. file_path .. "': " .. tostring(read_err)
    return nil, error_message
  end
  return content, nil
end

return scaffold
