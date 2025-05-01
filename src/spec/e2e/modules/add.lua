-- Pseudocode for src/spec/e2e/modules/add_spec.lua
local scaffold = require("src.spec.e2e.helpers.scaffold")

describe("almd add command (E2E)", function()
  local sandbox_path
  local cleanup_func

  -- Setup: Create a clean sandbox for each test
  before_each(function()
    sandbox_path, cleanup_func = scaffold.create_sandbox_project()
    -- Initialize a minimal project.lua if needed by the test case
    scaffold.init_project_file(sandbox_path, { name = "test-project", version = "0.1.0" })
  end)

  -- Teardown: Clean up the sandbox
  after_each(function()
    if cleanup_func then
      cleanup_func()
    end
  end)

  it("should add a file from GitHub using commit hash URL to default lib/", function()
    -- Arrange
    local url =
      "[https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua](https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua)"
    local expected_file_path = sandbox_path .. "/lib/shove.lua"
    local expected_proj_dep_key = "shove"
    local expected_proj_dep_val = "github:Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua" -- Or similar representation
    local expected_lock_path = "lib/shove.lua"
    local expected_lock_source = url -- Or the "raw" URL used
    local expected_lock_hash_prefix = "commit:81f7f87" -- Check commit hash source

    -- Act: Run `almd add <url>` within the sandbox
    local success, output = scaffold.run_almd(sandbox_path, { "add", url })

    -- Assert
    assert.is_true(success)
    -- 1. Check file download: Assert file exists at expected_file_path
    assert.is_true(scaffold.file_exists(expected_file_path))
    -- 2. Check project.lua: Assert dependency key/value exists
    local proj_data = scaffold.read_project_lua(sandbox_path)
    assert.are.equal(expected_proj_dep_val, proj_data.dependencies[expected_proj_dep_key])
    -- 3. Check almd-lock.lua: Assert package entry exists with correct path, source, and hash type/value
    local lock_data = scaffold.read_lock_lua(sandbox_path)
    local lock_entry = lock_data.package[expected_proj_dep_key]
    assert.is_not_nil(lock_entry)
    assert.are.equal(expected_lock_path, lock_entry.path)
    assert.are.equal(expected_lock_source, lock_entry.source) -- Adjust if raw URL is stored
    assert.truthy(string.match(lock_entry.hash, expected_lock_hash_prefix))
  end)

  it("should add a file from GitHub using commit hash URL to specified directory (-d)", function()
    -- Arrange
    local url =
      "[https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua](https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua)"
    local target_dir_rel = "src/engine/lib"
    local target_dir_abs = sandbox_path .. "/" .. target_dir_rel
    local expected_file_path = target_dir_abs .. "/shove.lua"
    local expected_proj_dep_key = "shove"
    -- project.lua might store source and path explicitly if not default
    local expected_proj_dep_val = { source = "github:...", path = target_dir_rel .. "/shove.lua" } -- Define structure
    local expected_lock_path = target_dir_rel .. "/shove.lua"

    -- Act: Run `almd add <url> -d <dir>`
    local success, output = scaffold.run_almd(sandbox_path, { "add", url, "-d", target_dir_rel })

    -- Assert
    assert.is_true(success)
    -- 1. Check file download: Assert file exists at expected_file_path (and dir created)
    assert.is_true(scaffold.file_exists(expected_file_path))
    -- 2. Check project.lua: Assert dependency has correct structure/values
    local proj_data = scaffold.read_project_lua(sandbox_path)
    assert.are.same(expected_proj_dep_val, proj_data.dependencies[expected_proj_dep_key]) -- Or check fields individually
    -- 3. Check almd-lock.lua: Assert package entry has correct path
    local lock_data = scaffold.read_lock_lua(sandbox_path)
    assert.are.equal(expected_lock_path, lock_data.package[expected_proj_dep_key].path)
    -- Check other lock fields (source, hash type) remain correct
    assert.truthy(string.match(lock_data.package[expected_proj_dep_key].hash, "commit:"))
  end)

  it("should add a file from GitHub using commit hash URL with specified directory (-d) and name (-n)", function()
    -- Arrange
    local url =
      "[https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua](https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua)"
    local target_dir_rel = "src/engine/lib"
    local dep_name = "clove"
    local expected_file_path = sandbox_path .. "/" .. target_dir_rel .. "/" .. dep_name .. ".lua"
    local expected_proj_dep_key = dep_name
    local expected_proj_dep_val = { source = "github:...", path = target_dir_rel .. "/" .. dep_name .. ".lua" } -- Define structure
    local expected_lock_path = target_dir_rel .. "/" .. dep_name .. ".lua"

    -- Act: Run `almd add <url> -d <dir> -n <name>`
    local success, output = scaffold.run_almd(sandbox_path, { "add", url, "-d", target_dir_rel, "-n", dep_name })

    -- Assert
    assert.is_true(success)
    -- 1. Check file download: Assert file exists with *new name* at expected_file_path
    assert.is_true(scaffold.file_exists(expected_file_path))
    -- 2. Check project.lua: Assert dependency uses *new key* and has correct structure/values
    local proj_data = scaffold.read_project_lua(sandbox_path)
    assert.is_not_nil(proj_data.dependencies[expected_proj_dep_key])
    assert.are.same(expected_proj_dep_val, proj_data.dependencies[expected_proj_dep_key]) -- Or check fields
    -- 3. Check almd-lock.lua: Assert package entry uses *new key* and has correct path
    local lock_data = scaffold.read_lock_lua(sandbox_path)
    assert.is_not_nil(lock_data.package[expected_proj_dep_key])
    assert.are.equal(expected_lock_path, lock_data.package[expected_proj_dep_key].path)
    -- Check other lock fields (source, hash type) remain correct
    assert.truthy(string.match(lock_data.package[expected_proj_dep_key].hash, "commit:"))
  end)

  it("should add a file from GitHub using branch URL, generating a sha256 hash", function()
    -- Arrange
    local url =
      "[https://github.com/Oval-Tutu/shove/blob/main/shove.lua](https://github.com/Oval-Tutu/shove/blob/main/shove.lua)" -- Uses branch 'main'
    local expected_file_path = sandbox_path .. "/lib/shove.lua"
    local expected_proj_dep_key = "shove"
    local expected_lock_path = "lib/shove.lua"
    local expected_lock_hash_prefix = "sha256:" -- Check calculated hash source

    -- Act: Run `almd add <url>`
    local success, output = scaffold.run_almd(sandbox_path, { "add", url })

    -- Assert
    assert.is_true(success)
    -- 1. Check file download: Assert file exists
    assert.is_true(scaffold.file_exists(expected_file_path))
    -- 2. Check project.lua: Assert dependency added (check key/value structure)
    local proj_data = scaffold.read_project_lua(sandbox_path)
    assert.is_not_nil(proj_data.dependencies[expected_proj_dep_key])
    -- 3. Check almd-lock.lua: Assert entry has correct path and sha256 hash
    local lock_data = scaffold.read_lock_lua(sandbox_path)
    local lock_entry = lock_data.package[expected_proj_dep_key]
    assert.is_not_nil(lock_entry)
    assert.are.equal(expected_lock_path, lock_entry.path)
    assert.truthy(string.match(lock_entry.hash, expected_lock_hash_prefix))
  end)

  it("should fail gracefully and inform user if the GitHub URL points to a non-existent file", function()
    -- Arrange
    local url =
      "[https://github.com/Oval-Tutu/shove/blob/main/non_existent_file.lua](https://github.com/Oval-Tutu/shove/blob/main/non_existent_file.lua)"
    local expected_file_path = sandbox_path .. "/lib/non_existent_file.lua"

    -- Act: Run `almd add <url>`
    local success, output = scaffold.run_almd(sandbox_path, { "add", url })

    -- Assert
    -- 1. Check command failed
    assert.is_false(success)
    -- 2. Check error message: Assert output contains informative error (e.g., "Failed to download", "File not found", URL)
    assert.truthy(string.match(output, "Failed") or string.match(output, "not found") or string.match(output, "Error"))
    -- 3. Check no file downloaded: Assert file does *not* exist
    assert.is_false(scaffold.file_exists(expected_file_path))
    -- 4. Check project.lua unchanged (or check no dependency added)
    local proj_data = scaffold.read_project_lua(sandbox_path)
    assert.is_nil(proj_data.dependencies or proj_data.dependencies["non_existent_file"])
    -- 5. Check almd-lock.lua unchanged (or check no lock entry added)
    local lock_data = scaffold.read_lock_lua(sandbox_path)
    assert.is_nil(lock_data or lock_data.package or lock_data.package["non_existent_file"])
  end)

  it("should add a file from a Gist URL, generating a sha256 hash", function()
    -- Arrange
    -- Example: Use a real raw Gist URL if possible for testing, replace placeholders otherwise
    local gist_raw_url = "https://gist.githubusercontent.com/anonymous/somegistid/raw/somecommithash/my_gist_lib.lua"
    local expected_dep_name = "my_gist_lib" -- Inferred from filename
    local expected_file_path = sandbox_path .. "/lib/" .. expected_dep_name .. ".lua"
    -- Based on current logic, project source will be the raw URL itself
    local expected_proj_dep_val = { source = gist_raw_url, path = "lib/" .. expected_dep_name .. ".lua" }
    local expected_lock_path = "lib/" .. expected_dep_name .. ".lua"
    local expected_lock_source = gist_raw_url -- Lock source should be the download URL used
    local expected_lock_hash_prefix = "sha256:"

    -- Act: Run `almd add <gist_url>`
    local success, output = scaffold.run_almd(sandbox_path, { "add", gist_raw_url })

    -- Assert
    assert.is_true(success, "Command should succeed. Output: " .. output)
    -- 1. Check file download
    assert.is_true(scaffold.file_exists(expected_file_path), "File should be downloaded to default lib path.")
    -- 2. Check project.lua
    local proj_data = scaffold.read_project_lua(sandbox_path)
    assert.is_not_nil(proj_data.dependencies, "Dependencies table should exist.")
    assert.is_not_nil(proj_data.dependencies[expected_dep_name], "Dependency key '" .. expected_dep_name .. "' should exist.")
    -- Verify source uses the raw URL and path is correct
    assert.are.same(expected_proj_dep_val, proj_data.dependencies[expected_dep_name], "Project dependency data mismatch.")
    -- 3. Check almd-lock.lua
    local lock_data = scaffold.read_lock_lua(sandbox_path)
    assert.is_not_nil(lock_data.package, "Lockfile package table should exist.")
    local lock_entry = lock_data.package[expected_dep_name]
    assert.is_not_nil(lock_entry, "Lockfile entry for '" .. expected_dep_name .. "' should exist.")
    assert.are.equal(expected_lock_path, lock_entry.path, "Lockfile path mismatch.")
    assert.are.equal(expected_lock_source, lock_entry.source, "Lockfile source mismatch.")
    assert.truthy(string.match(lock_entry.hash or "", expected_lock_hash_prefix), "Lockfile hash should start with 'sha256:'. Hash: " .. tostring(lock_entry.hash))
  end)

  -- Add more tests for edge cases:
  -- - Re-adding an existing dependency (should it update or error?)
  -- - Invalid URL formats
  -- - Network errors during download
  -- - Permissions issues writing files/directories
end)
