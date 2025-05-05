-- E2E Test Scaffolding Helpers
-- Provides functions to create isolated test environments (sandboxes),
-- run almd commands within them, and interact with project files.

local scaffold = {}

-- Attempt to load LuaFileSystem, but don't error if it's not present
local has_lfs, lfs = pcall(require, "lfs")

-- Require the main module to call run_cli directly
-- Assuming tests are run from the `src` directory
local has_main, main_module = pcall(require, "main")
if not has_main then
  error("Failed to require src/main.lua: " .. tostring(main_module))
end

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

-- Executes the almd command targeting the sandbox directory by calling main.run_cli directly.
-- Captures output and simulates exit behavior.
-- args_table should be a list of command-line arguments (e.g., {"add", "url", "-d", "path"})
-- Returns success (boolean), combined output (string), stderr (string - typically empty now).
function scaffold.run_almd(sandbox_path, args_table)
  -- LFS is required for chdir
  if not has_lfs then
    return false, "Error: LuaFileSystem (lfs) is required for robust sandbox testing but not found.", ""
  end
  if not main_module or not main_module.run_cli then
    return false, "Error: src/main.lua did not load correctly or missing run_cli function.", ""
  end

  local original_dir = lfs.currentdir()
  local original_package_path = package.path

  -- Construct paths relative to the original directory
  local src_lua_path = original_dir .. "/src/?.lua"
  local src_init_path = original_dir .. "/src/?/init.lua"
  -- Add other paths if main.lua adds more complex ones, e.g., src/lib
  local src_lib_path = original_dir .. "/src/lib/?.lua"

  local chdir_ok, chdir_err = pcall(lfs.chdir, sandbox_path)
  if not chdir_ok then
    return false, "Failed to chdir into sandbox '" .. sandbox_path .. "': " .. tostring(chdir_err), ""
  end

  -- Temporarily adjust package.path after chdir
  local temp_package_path = src_lua_path .. ";" .. src_init_path .. ";" .. src_lib_path .. ";" .. package.path

  -- Store originals and setup capture variables
  local original_print = print
  local original_exit = os.exit
  local previous_package_path = package.path -- Store before modifying
  package.path = temp_package_path -- Apply temporary path

  local captured_prints = {}
  local captured_exit_code = nil

  -- Override print to capture output
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[i] = tostring(select(i, ...))
    end
    table.insert(captured_prints, table.concat(parts, "\t"))
  end

  -- Override os.exit to capture code and prevent termination
  _G.os.exit = function(code)
    captured_exit_code = code or 0 -- Default to 0 if no code provided
    -- Do not actually exit, just record the code
    -- error("os.exit called with code: " .. tostring(captured_exit_code)) -- Use error to stop execution if needed, but run_cli should handle flow
  end

  local run_cli_ok, run_cli_message
  local execution_ok, execution_result = pcall(main_module.run_cli, args_table)

  -- Restore originals immediately after call
  _G.print = original_print
  _G.os.exit = original_exit

  -- Change back to original directory
  package.path = previous_package_path -- Restore package.path *before* chdir back
  local chback_ok, chback_err = pcall(lfs.chdir, original_dir)
  if not chback_ok then
    print("Warning: Failed to chdir back to original directory '" .. original_dir .. "': " .. tostring(chback_err))
    -- Continue, but state might be affected for subsequent tests
  end

  -- Fully restore original package path *after* changing back, just in case
  package.path = original_package_path

  local final_success
  local final_output

  if not execution_ok then
    -- Error occurred *during* run_cli execution (uncaught error)
    final_success = false
    run_cli_message = "Error during run_cli execution: " .. tostring(execution_result)
  else
    -- run_cli completed, use its return values
    run_cli_ok = execution_result -- First return value is the success status
    run_cli_message = select(2, execution_result) or "" -- Second return value is the message

    -- Determine overall success: run_cli must return true AND os.exit must not have been called with a non-zero code
    final_success = run_cli_ok and (captured_exit_code == nil or captured_exit_code == 0 or captured_exit_code == true)
    -- Note: os.execute compatibility: Lua 5.1 os.execute returns 0 for success, true on Windows.
    -- Our overridden os.exit captures the code. `run_cli` itself returns boolean `ok`.
    -- So, true success is `run_cli_ok == true` and `captured_exit_code` is not failure (e.g., 1).
  end

  -- Combine returned message and captured prints
  local captured_print_str = table.concat(captured_prints, "\n")
  -- Decide order: message first, then prints? Or interleave? Let's put message first.
  final_output = run_cli_message
  if captured_print_str ~= "" then
    if final_output ~= "" then
      final_output = final_output .. "\n" .. captured_print_str
    else
      final_output = captured_print_str
    end
  end

  -- Return in the format expected by add_spec.lua
  return final_success, final_output or "", "" -- Return empty string for stderr
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
