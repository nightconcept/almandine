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

  -- Setup: Create a fresh sandbox before each test
  before_each(function()
    -- Create the sandbox directory
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
      -- Clear vars for safety, though before_each should overwrite them
      sandbox_path = nil
      cleanup_func = nil
    else
       print("Warning: No cleanup function available for sandbox: " .. tostring(sandbox_path))
    end
  end)

  -- Placeholder test to ensure the spec file is valid
  it("should run setup and teardown without errors", function()
    -- This test primarily verifies that before_each and after_each work
    assert.is_not_nil(sandbox_path)
    assert.is_function(cleanup_func)
    local exists = scaffold.file_exists(sandbox_path .. "/project.lua")
    assert.is_true(exists, "project.lua should exist after setup")
  end)

  -- Task 3.2: Add via Commit Hash (Default Path)
  it("should add a dependency from a specific commit URL to the default lib/ path", function()
    local test_url = "https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua"
    local expected_dep_name = "shove"
    local expected_file_name = "shove.lua"
    local expected_file_path_relative = "src/lib/" .. expected_file_name
    local expected_commit_hash = "81f7f879a812e4479493a88e646831d0f0409560"

    -- Run the add command
    local success, output = scaffold.run_almd(sandbox_path, {"add", test_url})
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

    assert.are.equal(expected_source_identifier, actual_proj_dep_entry.source,
                     "Dependency source identifier mismatch in project.lua")

    assert.are.equal(expected_file_path_relative, actual_proj_dep_entry.path,
                     "Dependency path mismatch in project.lua")

    -- Verify almd-lock.lua content
    -- Debug: Print raw lockfile content
    -- local lock_file_path = sandbox_path .. "/almd-lock.lua"
    -- local raw_lock_content, raw_read_err = scaffold.read_file(lock_file_path)
    -- print("\n[Debug Spec] Raw content of " .. lock_file_path .. ":")
    -- print(raw_lock_content or ("Error reading raw lockfile: " .. tostring(raw_read_err)))
    -- print("--- End Raw Lockfile Content ---")

    local lock_data, lock_err = scaffold.read_lock_lua(sandbox_path)
    assert.is_not_nil(lock_data, "Failed to read almd-lock.lua: " .. tostring(lock_err))
    assert.is_not_nil(lock_data.package, "Package table missing in almd-lock.lua")
    local dep_lock_info = lock_data.package and lock_data.package[expected_dep_name]
    assert.is_not_nil(dep_lock_info, "Dependency entry missing in almd-lock.lua for " .. expected_dep_name)

    assert.are.equal(expected_file_path_relative, dep_lock_info.path, "Lockfile path mismatch")
    -- Lockfile source should be the raw download URL used
    local expected_lock_source = string.format("https://raw.githubusercontent.com/Oval-Tutu/shove/%s/shove.lua", expected_commit_hash)
    assert.are.equal(expected_lock_source, dep_lock_info.source, "Lockfile source mismatch")
    local expected_hash = "commit:" .. expected_commit_hash
    assert.are.equal(expected_hash, dep_lock_info.hash, "Lockfile hash mismatch (should be commit hash)")
  end)

  --[[ E2E Test Template for `almd add`

  it("should handle adding <description of test case, e.g., custom path, custom name>", function()
    -- 1. Define Test Case Variables
    local test_input_url = "<URL for the test>"
    local almd_args = {"add", test_input_url} -- Base arguments
    -- Add specific flags if needed (e.g., -d, -n)
    -- table.insert(almd_args, "-d")
    -- table.insert(almd_args, "<custom_path_or_dir>")
    -- table.insert(almd_args, "-n")
    -- table.insert(almd_args, "<custom_name>")

    local expected_dep_name = "<name expected in manifests (might be custom_name)>")
    local expected_file_name = "<filename expected (might be custom_name.lua)>")
    local expected_file_path_relative = "<path relative to sandbox root, e.g., src/custom/path/custom_name.lua>"
    local expected_ref = "<commit hash, branch, or tag expected in source identifier>"
    local expected_hash_prefix = "<commit: or sha256:>"
    local expected_hash_value = "<the actual commit hash or expected sha256>" -- Note: SHA will require downloading the file manually first to get its hash

    -- 2. Run `almd add`
    local success, output = scaffold.run_almd(sandbox_path, almd_args)
    assert.is_true(success, "almd add command should exit successfully. Output:\\n" .. output)

    -- 3. Verify File Download
    local expected_file_path_absolute = sandbox_path .. "/" .. expected_file_path_relative
    local file_exists = scaffold.file_exists(expected_file_path_absolute)
    assert.is_true(file_exists, "Expected file " .. expected_file_path_relative .. " was not found.")
    -- Optional: Verify file content hash if expected_hash_prefix is "sha256:"
    -- local hash_utils = require("utils.hash")
    -- local actual_content_hash, hash_err = hash_utils.hash_file_sha256(expected_file_path_absolute)
    -- assert.is_not_nil(actual_content_hash, "Failed to hash downloaded file: " .. tostring(hash_err))
    -- assert.are.equal(expected_hash_value, actual_content_hash, "Downloaded file content hash mismatch")

    -- 4. Verify project.lua
    local project_data, proj_err = scaffold.read_project_lua(sandbox_path)
    assert.is_not_nil(project_data, "Failed to read project.lua: " .. tostring(proj_err))
    assert.is_not_nil(project_data.dependencies, "Dependencies table missing in project.lua")
    local actual_proj_dep_entry = project_data.dependencies[expected_dep_name]
    assert.is_table(actual_proj_dep_entry, "Project dependency entry should be a table.")

    local url_utils = require("utils.url")
    -- Use the *input* URL to generate the expected identifier stored in project.lua
    local expected_source_identifier, id_err = url_utils.create_github_source_identifier(test_input_url)
    assert.is_not_nil(expected_source_identifier, "Failed to create expected source identifier: " .. tostring(id_err))

    assert.are.equal(expected_source_identifier, actual_proj_dep_entry.source, "Project source identifier mismatch")
    -- The path in project.lua should match the resolved relative path
    assert.are.equal(expected_file_path_relative, actual_proj_dep_entry.path, "Project path mismatch")

    -- 5. Verify almd-lock.lua
    local lock_data, lock_err = scaffold.read_lock_lua(sandbox_path)
    assert.is_not_nil(lock_data, "Failed to read almd-lock.lua: " .. tostring(lock_err))
    assert.is_not_nil(lock_data.package, "Package table missing in almd-lock.lua")
    local dep_lock_info = lock_data.package[expected_dep_name]
    assert.is_not_nil(dep_lock_info, "Dependency entry missing in almd-lock.lua for " .. expected_dep_name)

    -- The path in lockfile should also match the resolved relative path
    assert.are.equal(expected_file_path_relative, dep_lock_info.path, "Lockfile path mismatch")

    -- The source in lockfile should be the raw download URL used for the specific ref
    local _, _, _, expected_lock_source = url_utils.normalize_github_url(test_input_url) -- Get download URL from normalization
    assert.is_not_nil(expected_lock_source, "Could not determine expected raw download URL for lockfile source check")
    assert.are.equal(expected_lock_source, dep_lock_info.source, "Lockfile source mismatch (should be raw URL)")

    -- Verify the hash prefix and value
    local expected_hash = expected_hash_prefix .. expected_hash_value
    assert.are.equal(expected_hash, dep_lock_info.hash, "Lockfile hash mismatch")
  end)

  ]]

  -- Task 3.3: Add via Commit Hash (Custom Path -d)
  it("should add a dependency from a specific commit URL to a custom path using -d", function()
    -- 1. Define Test Case Variables
    local test_input_url = "https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua"
    local custom_dir = "src/engine/lib"
    local almd_args = {"add", test_input_url, "-d", custom_dir}

    local expected_dep_name = "shove"
    local expected_file_name = "shove.lua"
    local expected_file_path_relative = custom_dir .. "/" .. expected_file_name -- "src/engine/lib/shove.lua"
    local expected_commit_hash = "81f7f879a812e4479493a88e646831d0f0409560"
    local expected_hash_prefix = "commit:"
    local expected_hash_value = expected_commit_hash

    -- 2. Run `almd add`
    local success, output = scaffold.run_almd(sandbox_path, almd_args)
    assert.is_true(success, "almd add command should exit successfully. Output:\n" .. output)

    -- 3. Verify File Download
    local expected_file_path_absolute = sandbox_path .. "/" .. expected_file_path_relative
    local file_exists = scaffold.file_exists(expected_file_path_absolute)
    assert.is_true(file_exists, "Expected file " .. expected_file_path_relative .. " was not found.")

    -- 4. Verify project.lua
    local project_data, proj_err = scaffold.read_project_lua(sandbox_path)
    assert.is_not_nil(project_data, "Failed to read project.lua: " .. tostring(proj_err))
    assert.is_not_nil(project_data.dependencies, "Dependencies table missing in project.lua")
    local actual_proj_dep_entry = project_data.dependencies[expected_dep_name]
    assert.is_table(actual_proj_dep_entry, "Project dependency entry should be a table.")

    local url_utils = require("utils.url")
    -- Use the *input* URL to generate the expected identifier stored in project.lua
    local expected_source_identifier, id_err = url_utils.create_github_source_identifier(test_input_url)
    assert.is_not_nil(expected_source_identifier, "Failed to create expected source identifier: " .. tostring(id_err))

    assert.are.equal(expected_source_identifier, actual_proj_dep_entry.source, "Project source identifier mismatch")
    -- The path in project.lua should match the resolved relative path
    assert.are.equal(expected_file_path_relative, actual_proj_dep_entry.path, "Project path mismatch")

    -- 5. Verify almd-lock.lua
    local lock_data, lock_err = scaffold.read_lock_lua(sandbox_path)
    assert.is_not_nil(lock_data, "Failed to read almd-lock.lua: " .. tostring(lock_err))
    assert.is_not_nil(lock_data.package, "Package table missing in almd-lock.lua")
    local dep_lock_info = lock_data.package[expected_dep_name]
    assert.is_not_nil(dep_lock_info, "Dependency entry missing in almd-lock.lua for " .. expected_dep_name)

    -- The path in lockfile should also match the resolved relative path
    assert.are.equal(expected_file_path_relative, dep_lock_info.path, "Lockfile path mismatch")

    -- The source in lockfile should be the raw download URL used for the specific ref
    -- Note: create_github_source_identifier returns user/repo/path@ref which is not the raw url
    -- We need the actual download URL which normalize_github_url should provide
    local _, _, _, expected_lock_source = url_utils.normalize_github_url(test_input_url)
    assert.is_not_nil(expected_lock_source, "Could not determine expected raw download URL for lockfile source check")
    assert.are.equal(expected_lock_source, dep_lock_info.source, "Lockfile source mismatch (should be raw URL)")

    -- Verify the hash prefix and value
    local expected_hash = expected_hash_prefix .. expected_hash_value
    assert.are.equal(expected_hash, dep_lock_info.hash, "Lockfile hash mismatch")
  end)

  -- Future tests for `add` functionality will go here...

end)
