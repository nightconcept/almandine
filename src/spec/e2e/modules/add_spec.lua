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

  -- Add via Commit Hash to a custom path
  -- Equivalent to:
  -- almd add https://github.com/Oval-Tutu/shove/blob/(HASH)/shove.lua -d src/engine/lib
  it("should add a dependency from a specific commit URL to a custom path", function()
    local test_url = "https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua"
    local cmd_test_path = "src/engine/lib/" -- Path passed to the command (needs trailing slash)
    -- Note: Keep expected_dir separate for file existence check
    local expected_dir = "src/engine/lib" 
    local expected_dep_name = "shove"
    local expected_file_name = "shove.lua"
    -- Path expected in project.lua/lockfile reflects the add command's behavior (double slash)
    local expected_manifest_path_relative = cmd_test_path .. expected_file_name
    -- Path expected for file existence check (single slash, OS usually handles this)
    local expected_fs_path_relative = expected_dir .. "/" .. expected_file_name 
    local expected_commit_hash = "81f7f879a812e4479493a88e646831d0f0409560"

    -- Run the add command using the command path
    local success, output = scaffold.run_almd(sandbox_path, { "add", test_url, "-d", cmd_test_path })
    assert.is_true(success, "almd add command should exit successfully (exit code 0). Output:\n" .. output)

    -- Verify file downloaded to the custom path (using the filesystem-friendly path)
    local expected_file_path_absolute = sandbox_path .. "/" .. expected_fs_path_relative
    local file_exists = scaffold.file_exists(expected_file_path_absolute)
    print("DEBUG: Expected file path absolute: " .. expected_file_path_absolute)
    assert.is_true(file_exists, "Expected file " .. expected_file_path_absolute .. " was not found.")

    -- Verify project.lua content (expecting the double-slash path)
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

    -- Assert against the path with the double slash, as produced by add.lua
    assert.are.equal(expected_manifest_path_relative, actual_proj_dep_entry.path, "Dependency path mismatch in project.lua")

    -- Verify almd-lock.lua content (expecting the double-slash path)
    local lock_data, lock_err = scaffold.read_lock_lua(sandbox_path)
    assert.is_not_nil(lock_data, "Failed to read almd-lock.lua: " .. tostring(lock_err))
    assert.is_not_nil(lock_data.package, "Package table missing in almd-lock.lua")
    local dep_lock_info = lock_data.package and lock_data.package[expected_dep_name]
    assert.is_not_nil(dep_lock_info, "Dependency entry missing in almd-lock.lua for " .. expected_dep_name)

    -- Assert against the path with the double slash, as produced by add.lua
    assert.are.equal(expected_manifest_path_relative, dep_lock_info.path, "Lockfile path mismatch")

    local expected_lock_source =
      string.format("https://raw.githubusercontent.com/Oval-Tutu/shove/%s/shove.lua", expected_commit_hash)
    assert.are.equal(expected_lock_source, dep_lock_info.source, "Lockfile source mismatch")
    local expected_hash = "commit:" .. expected_commit_hash
    assert.are.equal(expected_hash, dep_lock_info.hash, "Lockfile hash mismatch (should be commit hash)")
  end)

  -- Add via Commit Hash (Default Path)
  -- Equivalent to:
  -- almd add https://github.com/Oval-Tutu/shove/blob/(HASH)/shove.lua
  it("should add a dependency from a specific commit URL to the default lib/ path", function()
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
end)
