-- src/spec/e2e/modules/init_spec.lua
-- E2E Tests for the almd init command

local assert = require("luassert")
local scaffold = require("spec.e2e.helpers.scaffold")
local init_module = require("modules.init") -- Require the module under test

-- Helper function for deep copying tables (handles nested tables, not functions/userdata etc.)
local function deep_copy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deep_copy(orig_key)] = deep_copy(orig_value)
        end
        setmetatable(copy, deep_copy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

describe("almd init command (E2E)", function()
  local cleanup_func
  local sandbox_path -- Add variable to store the path

  before_each(function()
    -- Create a sandboxed project directory before each test.
    -- The init command is expected to create the project.lua file itself.
    local path
    path, cleanup_func = scaffold.create_sandbox_project() -- Capture both return values
    sandbox_path = path -- Store the path
    assert.is_string(sandbox_path, "Sandbox creation should return a path string")
    assert.is_function(cleanup_func, "Sandbox creation should return a cleanup function")
  end)

  after_each(function()
    -- Clean up the sandboxed directory after each test.
    if cleanup_func then
      cleanup_func()
    end
  end)

  -- Test cases for 'almd init' will go here.
  -- it("should have a placeholder test", function()
  --   -- Placeholder test to ensure the spec file runs
  --   assert.is_true(true)
  -- end)

  it("should initialize project.lua with default values", function()
    -- 1. Prepare Mock Dependencies
    local captured_output = {}
    local mock_deps = {
      prompt = function(_msg, _default)
        -- Always return nil to accept the default value
        return nil
      end,
      println = function(...)
        -- Capture output for potential future assertions (optional)
        table.insert(captured_output, table.concat({...}, "\\t"))
      end,
      save_manifest = function(manifest)
        -- Use scaffold to write the file in the sandbox
        local ok, err = scaffold.init_project_file(sandbox_path, manifest)
        if not ok then
          print("Mock save_manifest error: " .. tostring(err)) -- Debug print
        end
        return ok, err -- Return status and error message (if any)
      end,
      exit = function(code)
        error("mock exit called with code: " .. tostring(code)) -- Fail test if exit is called
      end,
      printer = { -- Mock printer object
        stdout = function(...) table.insert(captured_output, table.concat({...}, "\\t")) end,
        stderr = function(...) table.insert(captured_output, "[STDERR] " .. table.concat({...}, "\\t")) end,
      }
    }

    -- 2. Run the init_project function
    local success, message = init_module.init_project(mock_deps)

    -- 3. Assertions
    assert.is_true(success, "init_project should return success=true")
    assert.is_string(message, "init_project should return a success message")
    -- print("Captured output:\\n" .. table.concat(captured_output, "\\n")) -- Uncomment for debugging output

    -- Verify project.lua content
    local manifest_content, read_err = scaffold.read_project_lua(sandbox_path)
    assert.is_nil(read_err, "Reading project.lua should not produce an error")
    assert.is_table(manifest_content, "Manifest content should be a table")

    local expected_manifest = {
      name = "my-lua-project",
      type = "application", -- Added in init.lua
      version = "0.0.1",
      license = "MIT",
      description = "A sample Lua project using Almandine.",
      scripts = {
        run = "lua src/main.lua" -- Default script
      },
      dependencies = {} -- No dependencies by default
    }

    assert.are.same(expected_manifest, manifest_content, "Manifest content should match defaults")

    -- Check if the file actually exists (optional, read_project_lua implies it)
    local file_path = sandbox_path .. (package.config:sub(1, 1) == '\\\\' and '\\\\' or '/') .. "project.lua"
    local f = io.open(file_path, "r")
    assert.is_not_nil(f, "project.lua file should exist in the sandbox")
    if f then f:close() end
  end)

  it("should initialize project.lua with custom values", function()
    -- 1. Define Custom Inputs
    local custom_inputs = {
      name = "my-custom-project",
      version = "1.2.3",
      license = "Apache-2.0",
      description = "A very specific test project.",
      scripts = {
        build = "tsc -p .",
        lint = "luacheck .",
      },
      dependencies = {
        lfs = "latest",
        busted = "~2.0",
      }
    }
    -- Keep track of which script/dep we are adding
    local script_index = 1
    local dep_index = 1
    local script_names = {}
    for k, _ in pairs(custom_inputs.scripts) do table.insert(script_names, k) end
    local dep_names = {}
    for k, _ in pairs(custom_inputs.dependencies) do table.insert(dep_names, k) end

    -- 2. Prepare Mock Dependencies
    local captured_output = {}
    local mock_deps = {
      prompt = function(msg, _default)
        -- Return custom values based on the prompt message
        if msg:find("Project name", 1, true) then
          return custom_inputs.name
        elseif msg:find("Project version", 1, true) then
          return custom_inputs.version
        elseif msg:find("License", 1, true) then
          return custom_inputs.license
        elseif msg:find("Description", 1, true) then
          return custom_inputs.description
        elseif msg:find("Script name", 1, true) then
          local name = script_names[script_index]
          script_index = script_index + 1
          return name -- Return nil/empty when out of bounds to stop loop
        elseif msg:find("Command for", 1, true) then
          -- Extract script name from prompt (e.g., "Command for 'build'")
          local name = msg:match("Command for '([^']+)'")
          return custom_inputs.scripts[name]
        elseif msg:find("Dependency name", 1, true) then
          local name = dep_names[dep_index]
          dep_index = dep_index + 1
          return name -- Return nil/empty when out of bounds to stop loop
        elseif msg:find("Version/source for", 1, true) then
           -- Extract dep name from prompt
          local name = msg:match("Version/source for '([^']+)'")
          return custom_inputs.dependencies[name]
        end
        -- Default case: return nil to accept potential defaults or break loops
        return nil
      end,
      println = function(...) table.insert(captured_output, table.concat({...}, "\\t")) end,
      save_manifest = function(manifest)
        local ok, err = scaffold.init_project_file(sandbox_path, manifest)
        return ok, err
      end,
      exit = function(code) error("mock exit called with code: " .. tostring(code)) end,
      printer = { -- Mock printer object
        stdout = function(...) table.insert(captured_output, table.concat({...}, "\\t")) end,
        stderr = function(...) table.insert(captured_output, "[STDERR] " .. table.concat({...}, "\\t")) end,
      }
    }

    -- 3. Run the init_project function
    local success, message = init_module.init_project(mock_deps)

    -- 4. Assertions
    assert.is_true(success, "init_project should return success=true for custom values")
    assert.is_string(message, "init_project should return a success message for custom values")
    -- print("Custom Captured output:\\n" .. table.concat(captured_output, "\\n")) -- Uncomment for debugging

    -- Verify project.lua content
    local manifest_content, read_err = scaffold.read_project_lua(sandbox_path)
    assert.is_nil(read_err, "Reading custom project.lua should not produce an error")
    assert.is_table(manifest_content, "Custom manifest content should be a table")

    -- Expected manifest MUST include the default 'run' script if not overridden
    local expected_manifest = deep_copy(custom_inputs) -- Use deep_copy instead of vim.deepcopy
    expected_manifest.type = "application" -- Added in init.lua
    if not expected_manifest.scripts["run"] then
        expected_manifest.scripts["run"] = "lua src/main.lua"
    end

    assert.are.same(expected_manifest, manifest_content, "Manifest content should match custom inputs")
  end)

  it("should overwrite existing project.lua with custom values", function()
    -- 1. Create Initial Dummy project.lua
    local dummy_manifest = {
      name = "dummy-project",
      version = "0.0.0",
      description = "This should be overwritten.",
      license = "None",
      scripts = { test = "echo 'old'" },
      dependencies = { old_dep = "1.0" }
    }
    local ok_init, err_init = scaffold.init_project_file(sandbox_path, dummy_manifest)
    assert.is_true(ok_init, "Should be able to create the initial dummy project file: " .. tostring(err_init))

    -- 2. Define Custom Inputs for Overwriting
    local custom_inputs = {
      name = "overwritten-project",
      version = "9.9.9",
      license = "Unlicense",
      description = "This is the new content.",
      scripts = {
        start = "node main.js",
      },
      dependencies = {
        new_dep = ">=1.0"
      }
    }
    -- Keep track of which script/dep we are adding
    local script_index = 1
    local dep_index = 1
    local script_names = {}
    for k, _ in pairs(custom_inputs.scripts) do table.insert(script_names, k) end
    local dep_names = {}
    for k, _ in pairs(custom_inputs.dependencies) do table.insert(dep_names, k) end

    -- 3. Prepare Mock Dependencies (similar to the custom values test)
    local captured_output = {}
    local mock_deps = {
      prompt = function(msg, _default)
        if msg:find("Project name", 1, true) then return custom_inputs.name end
        if msg:find("Project version", 1, true) then return custom_inputs.version end
        if msg:find("License", 1, true) then return custom_inputs.license end
        if msg:find("Description", 1, true) then return custom_inputs.description end
        if msg:find("Script name", 1, true) then
          local name = script_names[script_index]
          script_index = script_index + 1
          return name
        end
        if msg:find("Command for", 1, true) then
          local name = msg:match("Command for '([^']+)'")
          return custom_inputs.scripts[name]
        end
        if msg:find("Dependency name", 1, true) then
          local name = dep_names[dep_index]
          dep_index = dep_index + 1
          return name
        end
        if msg:find("Version/source for", 1, true) then
          local name = msg:match("Version/source for '([^']+)'")
          return custom_inputs.dependencies[name]
        end
        return nil -- Default case
      end,
      println = function(...) table.insert(captured_output, table.concat({...}, "\\\\t")) end,
      save_manifest = function(manifest)
        -- Overwrite the file in the sandbox
        local ok, err = scaffold.init_project_file(sandbox_path, manifest)
        return ok, err
      end,
      exit = function(code) error("mock exit called with code: " .. tostring(code)) end,
      printer = {
        stdout = function(...) table.insert(captured_output, table.concat({...}, "\\\\t")) end,
        stderr = function(...) table.insert(captured_output, "[STDERR] " .. table.concat({...}, "\\\\t")) end,
      }
    }

    -- 4. Run the init_project function
    local success, message = init_module.init_project(mock_deps)

    -- 5. Assertions
    assert.is_true(success, "init_project should return success=true when overwriting")
    assert.is_string(message, "init_project should return a success message when overwriting")

    -- Verify project.lua content has been overwritten
    local manifest_content, read_err = scaffold.read_project_lua(sandbox_path)
    assert.is_nil(read_err, "Reading overwritten project.lua should not produce an error")
    assert.is_table(manifest_content, "Overwritten manifest content should be a table")

    -- Expected manifest includes defaults ('type', 'run' script) if not overridden
    local expected_manifest = deep_copy(custom_inputs)
    expected_manifest.type = "application"
    if not expected_manifest.scripts["run"] then
        expected_manifest.scripts["run"] = "lua src/main.lua"
    end

    assert.are.same(expected_manifest, manifest_content,
      "Manifest content should match the new custom inputs, overwriting the old ones")
    -- Double-check the dummy values are gone
    assert.is_nil(manifest_content.dependencies.old_dep, "Old dummy dependency should be gone")
    assert.is_not_equal(manifest_content.name, dummy_manifest.name,
      "Project name should be the new one, not the dummy one")
  end)

end)
