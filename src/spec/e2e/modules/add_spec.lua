--[[
  add_spec
  @module add_spec

  End-to-End Tests for the `add` command
]]

describe("E2E: `almd add` command", function()
  -- Require the scaffold helper
  -- Note the relative path from this spec file to the helper
  -- Use dot notation assuming busted runs relative to src/
  local scaffold = require("spec.e2e.helpers.scaffold")
  local assert = require("luassert")
  local url_utils = require("utils.url")

  -- Variables to hold sandbox info between tests
  local sandbox_path
  local cleanup_func
  local initial_project_data -- Optional: Can be customized per test if needed. TODO: Move to base scaffold functions

  -- TODO: Remove entire luacheck ignore
  --luacheck: ignore
  local LOCKSOURCE_GITHUB_RAW = "https://raw.githubusercontent.com/Oval-Tutu/shove/81f7f879a812e4479493a88e646831d0f0409560/shove.lua"

  before_each(function()
    local path, cleaner, err = scaffold.create_sandbox_project()
    assert.is_not_nil(path, "Failed to create sandbox: " .. tostring(err))
    sandbox_path = path
    cleanup_func = cleaner

    -- Initialize a basic project.lua file
    initial_project_data = { name = "e2e-add-test", version = "0.1.0", dependencies = {} }
    local success, init_err = scaffold.init_project_file(sandbox_path, initial_project_data)
    assert.is_true(success, "Failed to initialize project.lua: " .. tostring(init_err))
  end)

  -- Teardown: Clean up the sandbox after each test
  after_each(function()
    if cleanup_func then
      cleanup_func()
      sandbox_path = nil
      cleanup_func = nil
    else
      print("Warning: No cleanup function available for sandbox: " .. tostring(sandbox_path))
    end
  end)

  -- Ensure the spec file is valid and setup is done
  it("should run setup and teardown without errors", function()
    -- This test primarily verifies that before_each and after_each work
    assert.is_not_nil(sandbox_path)
    assert.is_function(cleanup_func)
    local exists = scaffold.file_exists(sandbox_path .. "/project.lua")
    assert.is_true(exists, "project.lua should exist after setup")
  end)

  -- Helper function for verifying successful add cases
  -- TODO: Add params definitions
  local function _verify_add(params)
    -- Construct command arguments
    local cmd_args = { "add", params.url }
    if params.extra_args then
      for _, arg in ipairs(params.extra_args) do
        table.insert(cmd_args, arg)
      end
    end

    -- Default expect_success to true if not provided
    local expect_success = params.expect_success == nil or params.expect_success == true

    -- Capture initial state if expecting failure, to compare later
    local initial_dependencies
    if not expect_success then
      local initial_project_data_before, proj_err_before = scaffold.read_project_lua(sandbox_path)
      assert.is_not_nil(
        initial_project_data_before,
        string.format("Test '%s': Failed to read initial project.lua: %s", params.description, tostring(proj_err_before))
      )
      initial_dependencies = initial_project_data_before.dependencies or {}
    end

    -- TODO: Also run for coverage rather than success. Have run_almd also call the main path.
    -- Run the add command
    local success, output = scaffold.run_almd(sandbox_path, cmd_args)

    if expect_success then
      -- Assertions for successful add
      assert.is_true(
        success,
        string.format("Test '%s': almd add command failed. Output:\n%s", params.description, output)
      )

      -- Verify file downloaded
      local expected_file_path_absolute = sandbox_path .. "/" .. params.expected_file_path_relative
      local file_exists = scaffold.file_exists(expected_file_path_absolute)
      assert.is_true(
        file_exists,
        string.format(
          "Test '%s': Expected file %s was not found.",
          params.description,
          params.expected_file_path_relative
        )
      )

      -- Verify project.lua content
      local project_data, proj_err = scaffold.read_project_lua(sandbox_path)
      assert.is_not_nil(
        project_data,
        string.format("Test '%s': Failed to read project.lua: %s", params.description, tostring(proj_err))
      )
      assert.is_not_nil(
        project_data.dependencies,
        string.format("Test '%s': Dependencies table missing in project.lua", params.description)
      )
      local actual_proj_dep_entry = project_data.dependencies and project_data.dependencies[params.expected_dep_name]
      assert.is_table(
        actual_proj_dep_entry,
        string.format("Test '%s': Project dependency entry should be a table.", params.description)
      )

      local expected_source_identifier, id_err = url_utils.create_github_source_identifier(params.url)
      assert.is_not_nil(
        expected_source_identifier,
        string.format("Test '%s': Failed to create expected source identifier: %s", params.description, tostring(id_err))
      )
      assert.are.equal(
        expected_source_identifier,
        actual_proj_dep_entry.source,
        string.format("Test '%s': Dependency source identifier mismatch in project.lua", params.description)
      )
      assert.are.equal(
        params.expected_file_path_relative,
        actual_proj_dep_entry.path,
        string.format("Test '%s': Dependency path mismatch in project.lua", params.description)
      )

      -- Verify almd-lock.lua content
      local lock_data, lock_err = scaffold.read_lock_lua(sandbox_path)
      assert.is_not_nil(
        lock_data,
        string.format("Test '%s': Failed to read almd-lock.lua: %s", params.description, tostring(lock_err))
      )
      assert.is_not_nil(
        lock_data.package,
        string.format("Test '%s': Package table missing in almd-lock.lua", params.description)
      )
      local dep_lock_info = lock_data.package and lock_data.package[params.expected_dep_name]
      assert.is_not_nil(
        dep_lock_info,
        string.format(
          "Test '%s': Dependency entry missing in almd-lock.lua for %s",
          params.description,
          params.expected_dep_name
        )
      )

      assert.are.equal(
        params.expected_file_path_relative,
        dep_lock_info.path,
        string.format("Test '%s': Lockfile path mismatch", params.description)
      )
      assert.are.equal(
        params.expected_lock_source,
        dep_lock_info.source,
        string.format("Test '%s': Lockfile source mismatch", params.description)
      )

      local expected_hash = params.expected_hash_type .. ":" .. params.expected_hash_value
      assert.are.equal(
        expected_hash,
        dep_lock_info.hash,
        string.format("Test '%s': Lockfile hash mismatch", params.description)
      )
    else
      -- Assertions for failed add
      assert.is_false(
        success,
        string.format("Test '%s': almd add command should fail (exit code non-zero). Output:\n%s", params.description, output)
      )

      -- Verify file was NOT downloaded (check default location based on expected name)
      -- Note: assumes failure means no custom path/name was processed to create file.
      local default_file_path = sandbox_path .. "/src/lib/" .. params.expected_dep_name .. ".lua"
      local file_exists = scaffold.file_exists(default_file_path)
      assert.is_false(
        file_exists,
        string.format("Test '%s': Dependency file should NOT have been downloaded to %s", params.description, default_file_path)
      )

      -- Verify project.lua content remains unchanged
      local project_data_after, proj_err_after = scaffold.read_project_lua(sandbox_path)
      assert.is_not_nil(
        project_data_after,
        string.format("Test '%s': Failed to read project.lua after command: %s", params.description, tostring(proj_err_after))
      )
      assert.are.same(
        initial_dependencies,
        project_data_after.dependencies or {},
        string.format("Test '%s': project.lua dependencies table should remain unchanged.", params.description)
      )

      -- Verify almd-lock.lua was not created or remains unchanged
      local lock_file_path = sandbox_path .. "/almd-lock.lua"
      local lock_file_exists = scaffold.file_exists(lock_file_path)
      assert.is_false(
        lock_file_exists,
        string.format("Test '%s': almd-lock.lua should not have been created.", params.description)
      )
    end
  end

  local test_cases = {
    -- Equivalent to:
    -- almd add https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua
    {
      description = "should add a dependency from a specific commit URL to the default path",
      url = "https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua",
      extra_args = {},
      expected_dep_name = "shove",
      expected_file_path_relative = "src/lib/shove.lua",
      expected_hash_type = "commit",
      expected_hash_value = "81f7f879a812e4479493a88e646831d0f0409560",
      expected_lock_source = LOCKSOURCE_GITHUB_RAW,
      expect_success = true, -- Explicitly true (though default)
    },
    -- Equivalent to:
    -- almd add https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua
    -- -d src/engine/lib/
    {
      description = "should add a dependency from a specific commit URL to a custom path",
      url = "https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua",
      extra_args = { "-d", "src/engine/lib/" },
      expected_dep_name = "shove",
      expected_file_path_relative = "src/engine/lib/shove.lua",
      expected_hash_type = "commit",
      expected_hash_value = "81f7f879a812e4479493a88e646831d0f0409560",
      expected_lock_source = LOCKSOURCE_GITHUB_RAW,
      expect_success = true,
    },
    -- Equivalent to:
    -- almd add https://github.com/Oval-Tutu/shove/blob/main/shove.lua
    {
      description = "should add a dependency from a specific branch URL to the default path", -- Changed path
      url = "https://github.com/Oval-Tutu/shove/blob/main/shove.lua",
      extra_args = {}, -- Removed custom path args
      expected_dep_name = "shove",
      expected_file_path_relative = "src/lib/shove.lua", -- Default path
      expected_hash_type = "sha256",
      expected_hash_value = "7126e9d1ee584dc1a19612d3347cbf6e778cbaa859f7416ea51d0b360bd2223c",
      expected_lock_source = "https://raw.githubusercontent.com/Oval-Tutu/shove/main/shove.lua",
      expect_success = true,
    },
    -- Equivalent to:
    -- almd add https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua
    -- -d src/engine/lib/ -n clove
    {
      description = "should add a dependency from a specific commit URL to a custom path with a custom file name",
      url = "https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua",
      extra_args = { "-d", "src/engine/lib/", "-n", "clove" },
      expected_dep_name = "clove",
      expected_file_path_relative = "src/engine/lib/clove.lua",
      expected_hash_type = "commit",
      expected_hash_value = "81f7f879a812e4479493a88e646831d0f0409560",
      expected_lock_source = LOCKSOURCE_GITHUB_RAW,
      expect_success = true,
    },
    -- Equivalent to:
    -- almd add https://github.com/Oval-Tutu/shove/blob/main/clove.lua (non-existent file)
    {
      description = "should fail to add a dependency from a URL pointing to a non-existent file",
      url = "https://github.com/Oval-Tutu/shove/blob/main/clove.lua", -- Assuming clove.lua does not exist
      extra_args = {},
      expected_dep_name = "clove", -- Based on the non-existent file name
      expect_success = false,
      -- Other expected_ fields are omitted as they are not checked on failure
    },
  }

  -- Iterate over cases and run tests
  for _, test_case in ipairs(test_cases) do
    it(test_case.description, function()
      _verify_add(test_case)
    end)
  end
end)
