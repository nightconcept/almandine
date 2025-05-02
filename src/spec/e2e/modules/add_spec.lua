-- End-to-End Tests for the `add` command

describe("E2E: `almd add` command", function()
  -- Require the scaffold helper
  -- Note the relative path from this spec file to the helper
  -- Use dot notation assuming busted runs relative to src/
  local scaffold = require("spec.e2e.helpers.scaffold")
  local assert = require("luassert")

  -- Variables to hold sandbox info between tests
  local sandbox_path
  local cleanup_func
  local initial_project_data -- Optional: Can be customized per test if needed

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

  -- Add via Commit Hash (Default Path)
  -- Equivalent to:
  -- almd add https://github.com/Oval-Tutu/shove/blob/(HASH)/shove.lua
  it("should add a dependency from a specific commit URL to the default path", function()
    local test_url = "https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua"
    local expected_dep_name = "shove"
    local expected_file_name = "shove.lua"
    local expected_file_path_relative = "src/lib/" .. expected_file_name
    local expected_commit_hash = "81f7f879a812e4479493a88e646831d0f0409560"

    -- Run the add command
    local success, output = scaffold.run_almd(sandbox_path, { "add", test_url })
    assert.is_true(success, "almd add command should exit successfully (exit code 0). Output:\n" .. output)

    -- Verify file downloaded to the correct default location
    local expected_file_path_absolute = sandbox_path .. "/" .. expected_file_path_relative
    local file_exists = scaffold.file_exists(expected_file_path_absolute)
    assert.is_true(file_exists, "Expected file " .. expected_file_path_relative .. " was not found.")

    -- Verify project.lua content
    local project_data, proj_err = scaffold.read_project_lua(sandbox_path)
    assert.is_not_nil(project_data, "Failed to read project.lua: " .. tostring(proj_err))
    assert.is_not_nil(project_data.dependencies, "Dependencies table missing in project.lua")
    local actual_proj_dep_entry = project_data.dependencies and project_data.dependencies[expected_dep_name]
    assert.is_table(actual_proj_dep_entry, "Project dependency entry should be a table.")

    -- Calculate expected source identifier
    local url_utils = require("utils.url") -- Need this utility here
    local expected_source_identifier, id_err = url_utils.create_github_source_identifier(test_url)
    assert.is_not_nil(expected_source_identifier, "Failed to create expected source identifier: " .. tostring(id_err))

    assert.are.equal(
      expected_source_identifier,
      actual_proj_dep_entry.source,
      "Dependency source identifier mismatch in project.lua"
    )

    assert.are.equal(expected_file_path_relative, actual_proj_dep_entry.path, "Dependency path mismatch in project.lua")

    -- Verify almd-lock.lua content
    local lock_data, lock_err = scaffold.read_lock_lua(sandbox_path)
    assert.is_not_nil(lock_data, "Failed to read almd-lock.lua: " .. tostring(lock_err))
    assert.is_not_nil(lock_data.package, "Package table missing in almd-lock.lua")
    local dep_lock_info = lock_data.package and lock_data.package[expected_dep_name]
    assert.is_not_nil(dep_lock_info, "Dependency entry missing in almd-lock.lua for " .. expected_dep_name)

    assert.are.equal(expected_file_path_relative, dep_lock_info.path, "Lockfile path mismatch")

    local expected_lock_source =
      string.format("https://raw.githubusercontent.com/Oval-Tutu/shove/%s/shove.lua", expected_commit_hash)
    assert.are.equal(expected_lock_source, dep_lock_info.source, "Lockfile source mismatch")
    local expected_hash = "commit:" .. expected_commit_hash
    assert.are.equal(expected_hash, dep_lock_info.hash, "Lockfile hash mismatch (should be commit hash)")
  end)

  -- Add via Commit Hash to a custom path
  -- Equivalent to:
  -- almd add https://github.com/Oval-Tutu/shove/blob/(HASH)/shove.lua -d src/engine/lib
  it("should add a dependency from a specific commit URL to a custom path", function()
    local test_url = "https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua"
    local cmd_test_path = "src/engine/lib/"
    local expected_dir = "src/engine/lib"
    local expected_dep_name = "shove"
    local expected_file_name = "shove.lua"
    local expected_file_path_relative = expected_dir .. "/" .. expected_file_name
    local expected_commit_hash = "81f7f879a812e4479493a88e646831d0f0409560"

    -- Run the add command using the command path
    local success, output = scaffold.run_almd(sandbox_path, { "add", test_url, "-d", cmd_test_path })
    assert.is_true(success, "almd add command should exit successfully (exit code 0). Output:\n" .. output)

    -- Verify file downloaded to the custom path
    local expected_file_path_absolute = sandbox_path .. "/" .. expected_file_path_relative
    local file_exists = scaffold.file_exists(expected_file_path_absolute)
    assert.is_true(file_exists, "Expected file " .. expected_file_path_absolute .. " was not found.")

    -- Verify project.lua content
    local project_data, proj_err = scaffold.read_project_lua(sandbox_path)
    assert.is_not_nil(project_data, "Failed to read project.lua: " .. tostring(proj_err))
    assert.is_not_nil(project_data.dependencies, "Dependencies table missing in project.lua")
    local actual_proj_dep_entry = project_data.dependencies and project_data.dependencies[expected_dep_name]
    assert.is_table(actual_proj_dep_entry, "Project dependency entry should be a table.")

    -- Calculate expected source identifier
    local url_utils = require("utils.url") -- Need this utility here
    local expected_source_identifier, id_err = url_utils.create_github_source_identifier(test_url)
    assert.is_not_nil(expected_source_identifier, "Failed to create expected source identifier: " .. tostring(id_err))

    assert.are.equal(
      expected_source_identifier,
      actual_proj_dep_entry.source,
      "Dependency source identifier mismatch in project.lua"
    )

    -- Assert against the correct single-slash path
    assert.are.equal(expected_file_path_relative, actual_proj_dep_entry.path, "Dependency path mismatch in project.lua")

    -- Verify almd-lock.lua content (expecting single-slash path)
    local lock_data, lock_err = scaffold.read_lock_lua(sandbox_path)
    assert.is_not_nil(lock_data, "Failed to read almd-lock.lua: " .. tostring(lock_err))
    assert.is_not_nil(lock_data.package, "Package table missing in almd-lock.lua")
    local dep_lock_info = lock_data.package and lock_data.package[expected_dep_name]
    assert.is_not_nil(dep_lock_info, "Dependency entry missing in almd-lock.lua for " .. expected_dep_name)

    -- Assert against the correct single-slash path
    assert.are.equal(expected_file_path_relative, dep_lock_info.path, "Lockfile path mismatch")

    local expected_lock_source =
      string.format("https://raw.githubusercontent.com/Oval-Tutu/shove/%s/shove.lua", expected_commit_hash)
    assert.are.equal(expected_lock_source, dep_lock_info.source, "Lockfile source mismatch")
    local expected_hash = "commit:" .. expected_commit_hash
    assert.are.equal(expected_hash, dep_lock_info.hash, "Lockfile hash mismatch (should be commit hash)")
  end)


  -- Add via Branch to a custom path
  -- Equivalent to:
  -- almd add https://github.com/Oval-Tutu/shove/blob/(BRANCH)/shove.lua
  it("should add a dependency from a specific branch URL to a custom path", function()
    local test_url = "https://github.com/Oval-Tutu/shove/blob/main/shove.lua"
    local expected_dir = "src/lib"
    local expected_dep_name = "shove"
    local expected_file_name = "shove.lua"
    local expected_file_path_relative = expected_dir .. "/" .. expected_file_name
    local expected_branch = "main"
    local expected_commit_hash = "7126e9d1ee584dc1a19612d3347cbf6e778cbaa859f7416ea51d0b360bd2223c"

    -- Run the add command using the command path
    local success, output = scaffold.run_almd(sandbox_path, { "add", test_url })
    assert.is_true(success, "almd add command should exit successfully (exit code 0). Output:\n" .. output)

    -- Verify file downloaded to the custom path
    local expected_file_path_absolute = sandbox_path .. "/" .. expected_file_path_relative
    local file_exists = scaffold.file_exists(expected_file_path_absolute)
    assert.is_true(file_exists, "Expected file " .. expected_file_path_absolute .. " was not found.")

    -- Verify project.lua content
    local project_data, proj_err = scaffold.read_project_lua(sandbox_path)
    assert.is_not_nil(project_data, "Failed to read project.lua: " .. tostring(proj_err))
    assert.is_not_nil(project_data.dependencies, "Dependencies table missing in project.lua")
    local actual_proj_dep_entry = project_data.dependencies and project_data.dependencies[expected_dep_name]
    assert.is_table(actual_proj_dep_entry, "Project dependency entry should be a table.")

    -- Calculate expected source identifier
    local url_utils = require("utils.url") -- Need this utility here
    local expected_source_identifier, id_err = url_utils.create_github_source_identifier(test_url)
    assert.is_not_nil(expected_source_identifier, "Failed to create expected source identifier: " .. tostring(id_err))

    assert.are.equal(
      expected_source_identifier,
      actual_proj_dep_entry.source,
      "Dependency source identifier mismatch in project.lua"
    )

    assert.are.equal(expected_file_path_relative, actual_proj_dep_entry.path, "Dependency path mismatch in project.lua")

    -- Verify almd-lock.lua content (expecting single-slash path)
    local lock_data, lock_err = scaffold.read_lock_lua(sandbox_path)
    assert.is_not_nil(lock_data, "Failed to read almd-lock.lua: " .. tostring(lock_err))
    assert.is_not_nil(lock_data.package, "Package table missing in almd-lock.lua")
    local dep_lock_info = lock_data.package and lock_data.package[expected_dep_name]
    assert.is_not_nil(dep_lock_info, "Dependency entry missing in almd-lock.lua for " .. expected_dep_name)

    assert.are.equal(expected_file_path_relative, dep_lock_info.path, "Lockfile path mismatch")

    local expected_lock_source =
      string.format("https://raw.githubusercontent.com/Oval-Tutu/shove/%s/shove.lua", expected_branch)
    assert.are.equal(expected_lock_source, dep_lock_info.source, "Lockfile source mismatch")
    local expected_hash = "sha256:" .. expected_commit_hash
    assert.are.equal(expected_hash, dep_lock_info.hash, "Lockfile hash mismatch (should be commit hash)")
  end)


  -- Add via Commit Hash to a custom path with file name
  -- Equivalent to:
  -- almd add https://github.com/Oval-Tutu/shove/blob/(HASH)/shove.lua -d src/engine/lib
  -- -n clove
  it("should add a dependency from a specific commit URL to a custom path with a custom file name", function()
    local test_url = "https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua"
    local cmd_test_path = "src/engine/lib/"
    local cmd_test_name = "clove"
    local expected_dir = "src/engine/lib"
    local expected_dep_name = "clove"
    local expected_file_name = "clove.lua"
    local expected_file_path_relative = expected_dir .. "/" .. expected_file_name
    local expected_commit_hash = "81f7f879a812e4479493a88e646831d0f0409560"

    -- Run the add command using the command path
    local success, output = scaffold.run_almd(
      sandbox_path,
      { "add", test_url, "-d", cmd_test_path, "-n", cmd_test_name }
    )
    assert.is_true(success, "almd add command should exit successfully (exit code 0). Output:\n" .. output)

    -- Verify file downloaded to the custom path
    local expected_file_path_absolute = sandbox_path .. "/" .. expected_file_path_relative
    local file_exists = scaffold.file_exists(expected_file_path_absolute)
    assert.is_true(file_exists, "Expected file " .. expected_file_path_absolute .. " was not found.")

    -- Verify project.lua content (expecting single-slash path)
    local project_data, proj_err = scaffold.read_project_lua(sandbox_path)
    assert.is_not_nil(project_data, "Failed to read project.lua: " .. tostring(proj_err))
    assert.is_not_nil(project_data.dependencies, "Dependencies table missing in project.lua")
    local actual_proj_dep_entry = project_data.dependencies and project_data.dependencies[expected_dep_name]
    assert.is_table(actual_proj_dep_entry, "Project dependency entry should be a table.")

    -- Calculate expected source identifier
    local url_utils = require("utils.url")
    local expected_source_identifier, id_err = url_utils.create_github_source_identifier(test_url)
    assert.is_not_nil(expected_source_identifier, "Failed to create expected source identifier: " .. tostring(id_err))

    assert.are.equal(
      expected_source_identifier,
      actual_proj_dep_entry.source,
      "Dependency source identifier mismatch in project.lua"
    )

    assert.are.equal(expected_file_path_relative, actual_proj_dep_entry.path, "Dependency path mismatch in project.lua")

    -- Verify almd-lock.lua content
    local lock_data, lock_err = scaffold.read_lock_lua(sandbox_path)
    assert.is_not_nil(lock_data, "Failed to read almd-lock.lua: " .. tostring(lock_err))
    assert.is_not_nil(lock_data.package, "Package table missing in almd-lock.lua")
    local dep_lock_info = lock_data.package and lock_data.package[expected_dep_name]
    assert.is_not_nil(dep_lock_info, "Dependency entry missing in almd-lock.lua for " .. expected_dep_name)

    assert.are.equal(expected_file_path_relative, dep_lock_info.path, "Lockfile path mismatch")

    local expected_lock_source =
      string.format("https://raw.githubusercontent.com/Oval-Tutu/shove/%s/shove.lua", expected_commit_hash)
    assert.are.equal(expected_lock_source, dep_lock_info.source, "Lockfile source mismatch")
    local expected_hash = "commit:" .. expected_commit_hash
    assert.are.equal(expected_hash, dep_lock_info.hash, "Lockfile hash mismatch (should be commit hash)")
  end)
  -- Add a bad path (non-existent file)
  -- Equivalent to:
  -- almd add https://github.com/Oval-Tutu/shove/blob/main/clove.lua
  it("should fail to add a dependency from a URL pointing to a non-existent file", function()
    local test_url = "https://github.com/Oval-Tutu/shove/blob/main/clove.lua" -- Assuming clove.lua does not exist
    local expected_dep_name = "clove" -- Based on the non-existent file name

    -- Capture initial project state (dependencies)
    local initial_project_data_before, proj_err_before = scaffold.read_project_lua(sandbox_path)
    assert.is_not_nil(initial_project_data_before, "Failed to read initial project.lua: " .. tostring(proj_err_before))
    -- Handle case where dependencies might be nil
    local initial_dependencies = initial_project_data_before.dependencies or {}

    -- Run the add command using the command path - expect failure
    local success, output = scaffold.run_almd(sandbox_path, { "add", test_url })
    assert.is_false(success, "almd add command should fail (exit code non-zero). Output:\\n" .. output)

    -- Verify file was NOT downloaded (check default location and potential variations)
    local default_file_path = sandbox_path .. "/src/lib/" .. expected_dep_name .. ".lua"
    local file_exists = scaffold.file_exists(default_file_path)
    assert.is_false(
      file_exists,
      "Dependency file should NOT have been downloaded to " .. default_file_path
    )

    -- Verify project.lua content remains unchanged
    local project_data_after, proj_err_after = scaffold.read_project_lua(sandbox_path)
    assert.is_not_nil(
      project_data_after,
      "Failed to read project.lua after command: " .. tostring(proj_err_after)
    )
    assert.are.same(
      initial_dependencies,
      project_data_after.dependencies,
      "project.lua dependencies table should remain unchanged."
    )

    -- Verify almd-lock.lua was not created or remains unchanged (assuming it doesn't exist initially)
    local lock_file_path = sandbox_path .. "/almd-lock.lua"
    local lock_file_exists = scaffold.file_exists(lock_file_path)
    -- If the lock file COULD exist empty initially, we might need a different check,
    -- but the scaffold likely doesn't create it. So, just check for non-existence.
    assert.is_false(
      lock_file_exists,
      "almd-lock.lua should not have been created."
    )
  end)
end)
