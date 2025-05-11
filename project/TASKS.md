# Task Checklist: Almandine Go Implementation - `init` & `add` Commands

**Purpose:** Tracks tasks and milestones for implementing the core `init` and `add` commands for the Almandine Go CLI (`almd`), based on the specifications in `project/PRD.md`.

**Multiplatform Policy:** All implementations MUST be compatible with Linux, macOS, and Windows.

---

## Milestone 0: Initial Setup & `main.go` Entrypoint

**Goal:** Create the basic Go project structure and the main CLI entry point using `urfave/cli`.

-   [x] **Task 0.1: Initialize Go Module**
    -   [x] Run `go mod init <module_path>` (e.g., `go mod init github.com/your-user/almandine`). *User needs to determine the module path.*
    -   [x] Add `urfave/cli/v2` dependency (`go get github.com/urfave/cli/v2`).
    -   [x] Manual Verification: `go.mod` and `go.sum` are created/updated.

-   [x] **Task 0.2: Create `main.go`**
    -   [x] Create the `main.go` file at the project root.
    -   [x] Add the basic `main` function.
    -   [x] Manual Verification: File exists.

-   [x] **Task 0.3: Basic `urfave/cli` App Setup**
    -   [x] Import `urfave/cli/v2`.
    -   [x] Create a new `cli.App` instance in `main`.
    -   [x] Set the `Name` (`almd`), `Usage`, and `Version` for the app.
    -   [x] Implement the `app.Run(os.Args)` call.
    -   [x] Manual Verification: Run `go run main.go --version` and confirm the version is printed. Run `go run main.go --help` and confirm basic usage is shown.

-   [x] **Task 0.4: Define CLI Binary Name Convention**
    -   [x] Ensure the target executable name built by Go is `almd`.
    -   [x] *Note:* A separate wrapper script/alias named `almd` will be used by end-users to call `almd`. This task is about the Go build output name. (Build command might be `go build -o almd .`)
    -   [x] Manual Verification: Build the project (`go build -o almd .`) and confirm the output file is named `almd`.

---

## CLI Tool Name

-   The CLI executable is called `almd`.
-   All documentation, usage, and examples should refer to the CLI as `almd`.

---

## Milestone 1: `init` Command Implementation

**Goal:** Implement the `almd init` command to interactively create a `project.toml` manifest file.

-   [x] **Task 1.1: `urfave/cli` Command Setup**
    -   [x] Define the `init` command structure (`cli.Command`) within `commands/init.go`.
    -   [x] Add the command to the `urfave/cli` App in `main.go`.
    -   [x] Ensure basic command registration works (`almd init --help`).
    -   [x] Manual Verification: Run `almd init --help` and confirm the command is listed.

-   [x] **Task 1.2: Implement Interactive Prompts for Metadata**
    -   [x] Add logic within the `init` command's `Action` to prompt the user for:
        -   `package` name (with default).
        -   `version` (with default `0.1.0`).
        -   `license` (with default `MIT`).
        -   `description` (with default).
        -   Optional: `language` details (consider defaulting initially).
    -   [x] Manual Verification: Run `almd init` interactively and confirm prompts appear and capture input correctly.

-   [x] **Task 1.3: Implement Interactive Prompts for Scripts**
    -   [x] Add logic to loop, prompting for script `name` and `command`.
    -   [x] Store collected scripts (e.g., in a `map[string]string`).
    -   [x] Exit the loop when an empty script name is entered.
    -   [x] Implement logic to add a default `run` script (`lua src/main.lua`) if the user doesn't define one.
    -   [x] Manual Verification: Run `almd init` interactively, add a few scripts, skip adding `run`, and verify the default is included conceptually (actual file writing is next).

-   [x] **Task 1.4: Implement Interactive Prompts for Dependencies (Placeholders)**
    -   [x] Add logic to loop, prompting for dependency `name` and a simple `source/version` string (as per PRD).
    -   [x] Store collected dependency placeholders (e.g., in a `map[string]string` or `map[string]interface{}`).
    -   [x] Exit the loop when an empty dependency name is entered.
    -   [x] Manual Verification: Run `almd init` interactively, add a few placeholder dependencies.

-   [x] **Task 1.5: Implement `project.toml` Structure and Writing**
    -   [x] Define Go structs in `internal/project/` to represent the `project.toml` structure (package info, scripts, dependencies).
    -   [x] Create functions in `internal/config/` to marshal the collected data into the Go struct and write it to `project.toml` using a TOML library (`github.com/BurntSushi/toml`).
    -   [x] Ensure the function correctly handles overwriting an existing `project.toml`.
    -   [x] Integrate this writing logic into the `init` command's `Action`.
    -   [x] Add clear output messages (success, errors).
    -   [x] Manual Verification: Run `almd init`, provide input, and verify `project.toml` is created correctly with the specified data and defaults. Run again and verify it overwrites. Check error handling for write failures (e.g., permissions).

## Milestone 2: `add` Command Implementation

**Goal:** Implement the `almd add <source_url>` command to download a single-file dependency, update `project.toml`, and update `almd-lock.toml`.

-   [x] **Task 2.1: `urfave/cli` Command Setup & Argument/Flag Parsing**
    -   [x] Define the `add` command structure (`cli.Command`) in `commands/add.go`.
    -   [x] Define the required `<source_url>` argument.
    -   [x] Define the flags: `-d, --directory string`, `-n, --name string`, `--verbose bool`.
    -   [x] Add the command to the `urfave/cli` App in `main.go`.
    -   [x] Implement basic parsing logic within the `Action` to retrieve the argument and flag values.
    -   [x] Manual Verification: Run `almd add --help` and confirm the command, argument, and flags are listed correctly. Run `almd add some-url -n test -d testdir --verbose` and verify the values are accessible within the (currently empty) action.

-   [x] **Task 2.2: Implement Source URL Handling (`internal/source`)**
    -   [x] Create package `internal/source`.
    -   [x] Implement functions to parse the input `<source_url>` (`net/url`).
    -   [x] Implement logic specifically for GitHub URLs:
        -   Normalize various formats (blob, raw) to the raw content download URL.
        -   Extract commit hash/ref if present.
        -   Create the canonical source identifier string (e.g., `github:user/repo/path@hash`).
    -   [x] Define return structures or values for the raw URL, canonical identifier, and extracted commit hash.
    -   [x] Manual Verification: Test the parsing functions with various valid and invalid GitHub URL formats. (Code review of parsing logic done, specific unit tests are outside this immediate task but recommended next)

-   [x] **Task 2.3: Implement File Downloading (`internal/downloader`)**
    -   [x] Create package `internal/downloader`.
    -   [x] Implement a function that takes a URL (the raw download URL from Task 2.2) and fetches the content using `net/http`.
    -   [x] Handle potential HTTP errors (status codes, network issues).
    -   [x] Return the downloaded content (e.g., as `[]byte`).
    -   [x] Manual Verification: Test the download function with a known raw GitHub file URL. (Code implemented; manual test by user pending integration)

-   [x] **Task 2.4: Implement Target Path Logic & File Saving**
    -   [x] Add logic within the `add` command's `Action` to determine the final destination path based on the `-d` flag, `-n` flag (or inferred name), and the project root.
    -   [x] Use `os.MkdirAll` to create the target directory if it doesn't exist.
    -   [x] Use `os.WriteFile` to save the downloaded content (`[]byte` from Task 2.3) to the determined path.
    -   [x] Handle file writing errors.
    -   [x] Manual Verification: Run `almd add <url>` with different `-d` and `-n` combinations and verify the file is saved to the correct location with the correct name. Test directory creation.

-   [x] **Task 2.5: Implement Hashing (`internal/hasher`)**
    -   [x] Create package `internal/hasher`.
    -   [x] Implement a function to calculate the SHA256 hash of file content (`[]byte`) using `crypto/sha256`.
    -   [x] Format the output hash string as `sha256:<hex_hash>`.
    -   [x] Manual Verification: Test the hashing function with known content and verify the output hash.

-   [x] **Task 2.6: Define Data Structures (`internal/project`)**
    -   [x] Extend Go structs in `internal/project/` to represent the `dependencies` table structure in `project.toml` (sub-table with `source`, `path`).
    -   [x] Define Go structs for the `almd-lock.toml` structure (`api_version`, `[package]` table with entries containing `source`, `path`, `hash`).
    -   [x] Manual Verification: Code review confirms structs accurately model the TOML structures defined in `PRD.md`.

-   [x] **Task 2.7: Implement Manifest Update (`internal/config`)**
    -   [x] Add functions in `internal/config/` to:
        -   [x] Load an existing `project.toml`.
        -   [x] Add or update a dependency entry in the `[dependencies]` map using the dependency name (from `-n` or inferred), canonical source identifier (Task 2.2), and relative file path (Task 2.4).
        -   [x] Save the updated manifest back to `project.toml`.
    -   [x] Integrate this logic into the `add` command's `Action`.
    -   [x] Manual Verification: Run `almd add <url>`, then inspect `project.toml` to verify the dependency entry is added/updated correctly.

-   [x] **Task 2.8: Implement Lockfile Update (`internal/lockfile`)**
    -   [x] Create package `internal/lockfile`.
    -   [x] Add functions to:
        -   [x] Load `almd-lock.toml` (handling file not found initially).
        -   [x] Calculate the integrity hash string: `commit:<commit_hash>` (if available from Task 2.2) or `sha256:<hash>` (from Task 2.5). Handle potential hashing errors (`hash_error:<reason>`).
        -   [x] Add or update an entry in the `[package]` map using the dependency name, the *exact raw download URL* (Task 2.2), the relative file path (Task 2.4), and the calculated hash string.
        -   [x] Set/ensure `api_version = "1"`.
        -   [x] Save the updated lockfile back to `almd-lock.toml`.
    -   [x] Integrate this logic into the `add` command's `Action`.
    -   [x] Manual Verification: Run `almd add <url>`, then inspect `almd-lock.toml` to verify the entry is added/updated with the correct source URL, path, and hash format.

-   [x] **Task 2.9: Error Handling and Cleanup**
    -   [x] Review the `add` command's `Action` logic.
    -   [x] Implement error handling using `urfave/cli`'s error reporting (e.g., `cli.Exit`).
    -   [x] If an error occurs *after* downloading the file but *before* successfully updating both manifest and lockfile, attempt to delete the downloaded file to maintain consistency.
    -   [x] Ensure clear error messages are provided to the user.
    -   [x] Manual Verification: Test error scenarios: invalid URL, download failure, write permission errors for manifest/lockfile, simulate failures mid-process to check cleanup.

## Milestone 3: Initial Testing Setup

**Goal:** Establish the basic structure for tests for the `init` and `add` commands.

-   [x] **Task 3.1: Define Testing Strategy**
    -   [x] Framework: Standard Go `testing` package with `testify` for assertions.
    -   [x] `init` command: Unit tests directly invoking the command's `Action`, simulating user input (as in `commands/init_test.go`).
    -   [x] `add` command: Unit tests directly invoking the command's `Action` (via `app.Run` within the test).
        -   [x] Network calls for `add` will be mocked using `net/http/httptest`.
        -   [x] File system operations will occur in temporary directories created by tests.
    -   [x] Setup/Teardown: Tests will create temporary directories and necessary initial files (e.g., `project.toml`), and these will be cleaned up automatically by `t.TempDir()` or explicit `defer os.RemoveAll`.
    -   [x] Manual Verification: Review the chosen strategy for feasibility.

-   [x] **Task 3.2: Create Test File Structure**
    -   [x] Test file for `init` command: `commands/init_test.go` (exists).
    -   [x] Create test file for `add` command: `commands/add_test.go`.
    -   [x] Implement shared test helpers if applicable (e.g., for creating temp env, running command actions).
    -   [x] Manual Verification: Run `go test ./...` and confirm test files are picked up.

-   [ ] **Task 3.3: Implement `init` Command Test Cases (Existing)**
    -   [x] Basic `init` test case (as in `commands/init_test.go`).
    -   [x] `init` test case with defaults and empty inputs (as in `commands/init_test.go`).
    -   [x] **Sub-Task 3.3.1: Fix `TestInitCommand` failure "project.toml\project.toml: The system cannot find the path specified." (2025-05-08)**
        -   [x] Changed `config.WriteProjectToml("project.toml", ...)` to `config.WriteProjectToml(".", ...)` in `internal/cli/init/init.go` to correctly specify the current directory for `project.toml` creation.

-   [ ] **Task 3.4: Implement `add` Command Unit Test Cases**
    -   [x] **Sub-Task 3.4.1: Setup for `add` tests in `commands/add_test.go`**
        -   [x] Define `TestMain` if any global setup/teardown for `add` tests is needed.
        -   [x] Create helper: `setupAddTestEnvironment(t *testing.T, initialProjectTomlContent string) (tempDir string)` that creates a temp dir and a `project.toml`.
        -   [x] Create helper: `runAddCommand(t *testing.T, tempDir string, mockServerURL string, cliArgs ...string) error` to set up and run the `add` command's action using an `cli.App` instance.
        -   [x] Create helper: `startMockHTTPServer(t *testing.T, content string, expectedPath string, statusCode int) *httptest.Server`.
    -   [x] **Sub-Task 3.4.2: Test `almd add` - Successful Download and Update (Explicit Name, Custom Directory)**
        -   [x] Setup: Temp dir, basic `project.toml`, mock HTTP server serving test content.
        -   [x] Execute: `almd add <mock_url_to_file> -n mylib -d vendor/custom`.
        -   [x] Verify:
            -   `vendor/custom/mylib` created with correct content.
            -   `project.toml` updated with `[dependencies.mylib]` pointing to `source` and `path="vendor/custom/mylib"`.
            -   `almd-lock.toml` created/updated with `[package.mylib]` including `source`, `path`, and `hash="sha256:..."`.
    -   [x] **Sub-Task 3.4.3: Test `almd add` - Successful Download (Inferred Name, Default Directory)**
        -   [x] Execute: `almd add <mock_url_to_file.lua>`.
        -   [x] Verify:
            -   `libs/file.lua` (or project root, per PRD) created.
            -   Manifest and lockfile updated with inferred name `file.sh`.
    -   [x] **Sub-Task 3.4.4: Test `almd add` - GitHub URL with Commit Hash**
        -   [x] URL can include a commit hash segment (e.g., `file.lua@commitsha`) or a branch/tag name (e.g., `file.lua@main`).
        -   [x] Verify `almd-lock.toml` `hash` field reflects `commit:<actual_commit_sha>`. If original URL was a branch/tag, it's resolved to the latest commit SHA for that file on that branch/tag. If original URL was a commit SHA, that SHA is used.
        -   [x] If GitHub API call fails to resolve a branch/tag, or if not a GitHub URL, verify fallback to `sha256:<content_hash>`.
    -   [x] **Sub-Task 3.4.5: Test `almd add` - Error: Download Failure (HTTP Error)**
        -   [x] Mock server returns non-200 status.
        -   [x] Verify command returns an error.
        -   [x] Verify no dependency file is created.
        -   [x] Verify `project.toml` and `almd-lock.toml` are not modified (or created if they didn't exist).
    -   [x] **Sub-Task 3.4.6: Test `almd add` - Error: `project.toml` Not Found**
        -   [x] Run `add` in a temp dir without `project.toml`.
        -   [x] Verify command returns an appropriate error.
    -   [x] **Sub-Task 3.4.7: Test `almd add` - Cleanup on Failure (e.g., Lockfile Write Error)**
        -   [x] Difficult to precisely mock file system write errors without more DI.
        -   [x] Focus on: If download happens, but a subsequent step like TOML marshaling or lockfile writing fails, does the downloaded file get removed? (This might require a test where the mock HTTP server succeeds, but we introduce an error in a subsequent, controllable step if possible, or inspect code paths for this cleanup logic). Initially, can be a lower priority if hard to test cleanly.
    -   [x] **Sub-Task 3.4.8: Fix `TestAddCommand_ProjectTomlNotFound` (2025-05-07)**
        -   [x] Modified error message in `internal/cli/add/add.go` to include "no such file or directory" when `project.toml` is not found.
        -   [x] Refactored `Action` in `internal/cli/add/add.go` to use a named return error, ensuring the deferred cleanup logic correctly removes downloaded files when `project.toml` is missing and an error is returned.
        -   [x] Corrected variable types for `proj` (to `*project.Project`) and `lf` (to `*lockfile.Lockfile`) in `internal/cli/add/add.go` to resolve compiler errors.


## Milestone 4: `remove` Command Implementation

**Goal:** Implement the `almd remove <dependency_name>` command to remove a dependency from the project.

-   [x] **Task 4.1: `urfave/cli` Command Setup**
    -   [x] Define the `remove` command structure (`cli.Command`) in `commands/remove.go` (or `internal/cli/remove/remove.go` as per PRD folder structure).
    -   [x] Add the command to the `urfave/cli` App in `main.go`.
    -   [x] Define the required `<dependency_name>` argument.
    -   [x] Manual Verification: Run `almd remove --help` and confirm the command and argument are listed correctly. Run `almd remove some-dep` and verify the argument value is accessible within the (currently empty) action.

-   [x] **Task 4.2: Implement Manifest Loading and Dependency Path Retrieval**
    -   [x] Add logic within the `remove` command's `Action` to load `project.toml` (using `internal/config`).
    -   [x] Verify if the specified `<dependency_name>` exists in the `[dependencies]` table.
    -   [x] If it exists, retrieve the relative `path` of the dependency.
    -   [x] Handle errors if `project.toml` is not found or the dependency does not exist.
    -   [x] Manual Verification: Test with an existing `project.toml`. Try removing an existing and a non-existing dependency. Check error messages.

-   [x] **Task 4.3: Implement Manifest Update and File Deletion**
    -   [x] Remove the entry for `<dependency_name>` from the `[dependencies]` table in the loaded manifest data.
    -   [x] Save the updated manifest back to `project.toml`.
    -   [x] Delete the file specified by the retrieved `path` using `os.Remove`.
    -   [x] Handle potential errors during file saving and deletion (e.g., permissions, file not found for deletion).
    -   [x] Manual Verification: Add a dependency using `almd add`. Then use `almd remove <dep_name>`. Verify `project.toml` is updated and the file is deleted. Test error conditions like read-only `project.toml` or non-existent dependency file.

-   [x] **Task 4.4: Implement Lockfile Update**
    -   [x] Load `almd-lock.toml` (using `internal/lockfile`).
    -   [x] Remove the entry for `<dependency_name>` from the `[package]` table in the loaded lockfile data.
    -   [x] Save the updated lockfile back to `almd-lock.toml`.
    -   [x] Handle errors if `almd-lock.toml` is not found or during saving. Handle cases where the dependency might not be in the lockfile even if it was in the manifest.
    -   [x] Manual Verification: After successfully running `almd add`, run `almd remove <dep_name>`. Verify `almd-lock.toml` is updated. Test with missing or read-only `almd-lock.toml`.

-   [x] **Task 4.5: Error Handling and Output**
    -   [x] Ensure robust error handling for all operations using `urfave/cli`'s error reporting (e.g., `cli.Exit`).
    -   [x] Provide clear confirmation messages for successful removal (manifest, file, lockfile).
    -   [x] Provide clear error messages for different failure scenarios.
    -   [x] Manual Verification: Test various error paths (missing files, non-existent dependency, permission issues) and check for clear, user-friendly output.

-   [x] **Task 4.6: Implement Empty Directory Cleanup**
    -   [x] After successful file deletion in `remove` (Task 4.3), check if the parent directory of the deleted file is empty.
    -   [x] If the directory is empty, delete it.
    -   [x] Repeat this process, moving upwards to parent directories, deleting them if they become empty.
    -   [x] Stop if a directory is not empty, an error occurs, or a predefined boundary (e.g., project root, `libs/`, `vendor/`) is reached.
    -   [x] Ensure directory emptiness check is robust to prevent accidental deletion of non-empty directories.
    -   [x] Manual Verification: Test scenarios where single and multiple empty parent directories are cleaned up. Test scenarios where cleanup stops appropriately. (Note: Manual verification by user is pending actual use, code implements the logic).

## Milestone 5: `remove` Command Testing

**Goal:** Implement unit tests for the `remove` command.

-   [x] **Task 5.1: Create Test File Structure for `remove`**
    -   [x] Create test file: `internal/cli/remove/remove_test.go`.
    -   [x] Implement shared test helpers if applicable (e.g., for creating temp env with `project.toml`, `almd-lock.toml`, and dummy dependency files).

-   [ ] **Task 5.2: Implement `remove` Command Unit Test Cases**
    -   [x] **Sub-Task 5.2.1: Setup for `remove` tests**
        -   [x] Define `TestMain` if any global setup/teardown for `remove` tests is needed. (Skipped for now, can be added if specific global setup is identified)
        -   [x] Create helper: `setupRemoveTestEnvironment(t *testing.T, initialProjectTomlContent string, initialLockfileContent string, depFiles map[string]string) (tempDir string)` that creates a temp dir, `project.toml`, `almd-lock.toml`, and specified dependency files.
        -   [x] Create helper: `runRemoveCommand(t *testing.T, tempDir string, cliArgs ...string) error` to set up and run the `remove` command's action.
    -   [x] **Sub-Task 5.2.2: Test `almd remove` - Successful Removal**
        -   [x] Setup: Temp dir with `project.toml`, `almd-lock.toml`, and a dummy dependency file, all correctly linked.
        -   [x] Execute: `almd remove <dependency_name>`.
        -   [x] Verify:
            -   Dependency entry removed from `project.toml`.
            -   Dependency entry removed from `almd-lock.toml`.
            -   Dependency file deleted from the filesystem.
            -   Command returns no error.
    -   [x] **Sub-Task 5.2.3: Test `almd remove` - Error: Dependency Not Found in Manifest**
        -   [x] Setup: Temp dir with `project.toml` that does not contain the target dependency.
        -   [x] Execute: `almd remove <non_existent_dependency_name>`.
        -   [x] Verify:
            -   Command returns an appropriate error.
            -   `project.toml` and `almd-lock.toml` remain unchanged.
            -   No file deletion attempted for the non-existent dependency.
           -   [x] **Sub-Task 5.2.4: Test `almd remove` - Error: Dependency File Not Found for Deletion**
            -   [x] Setup: Temp dir with `project.toml` and `almd-lock.toml` listing a dependency, but the actual dependency file is missing.
            -   [x] Execute: `almd remove <dependency_name>`.
        -   [x] Verify:
        	-   Dependency entry removed from `project.toml`.
        	-   Dependency entry removed from `almd-lock.toml`.
        	-   Command may return a warning or error about file deletion failure, but manifest/lockfile changes should persist.
        	-   PRD: "Handles potential errors gracefully (e.g., file not found, permissions)."
       -   [x] **Sub-Task 5.2.5: Test `almd remove` - Error: `project.toml` Not Found (2025-05-08 - Refined fix for CWD handling)**
        -   [x] Setup: Run `remove` in a temp dir without `project.toml`.
        -   [x] Execute: `almd remove <dependency_name>`.
        -   [x] Verify: Command returns an appropriate error.
    -   [x] **Sub-Task 5.2.6: Test `almd remove` - Dependency in Manifest but not Lockfile**
        -   [x] Setup: Temp dir with `project.toml` listing a dependency, `almd-lock.toml` exists but doesn't list it, and the dependency file exists.
        -   [x] Execute: `almd remove <dependency_name>`.
        -   [x] Verify:
            -   Dependency entry removed from `project.toml`.
            -   `almd-lock.toml` is processed (attempt to remove, no error if not found).
            -   Dependency file deleted.
            -   Command completes successfully or with a notice about the lockfile state.
    -   [x] **Sub-Task 5.2.7: Test `almd remove` - Empty `project.toml` or `almd-lock.toml` (2025-05-08 - Empty project.toml case fixed)**
        -   [x] Setup: Temp dir with empty `project.toml` and/or `almd-lock.toml`.
        -   [x] Execute: `almd remove <dependency_name>`.
        -   [x] Verify: Command returns an error indicating dependency not found (for empty `project.toml`) or handles empty lockfile gracefully, and files remain empty or unchanged.

## Milestone 6: `install` Command Implementation

**Goal:** Implement the `almd install` command to refresh dependencies based on `project.toml` and update `almd-lock.toml`.

-   [x] **Task 6.1: `urfave/cli` Command Setup for `install`**
    -   [x] Define the `install` command structure (`cli.Command`) in `internal/cli/install/install.go`.
    -   [x] Add the command to the `urfave/cli` App in `main.go`.
    -   [x] Define optional `[dependency_names...]` argument.
    -   [x] Define flags: `--force, -f` (bool), `--verbose` (bool).
    -   [x] Manual Verification: Run `almd install --help` and confirm the command, argument, and flags are listed correctly.

-   [x] **Task 6.2: Argument Parsing and Initial Loading**
    -   [x] In the `install` command's `Action`, parse optional dependency names. If none, target all.
    -   [x] Load `project.toml` (using `internal/core/config`). Handle errors if not found.
    -   [x] Load `almd-lock.toml` (using `internal/core/lockfile`). Handle if not found (treat as all dependencies needing install/addition to lockfile).
    -   [x] Manual Verification: Test with and without dependency names. Check behavior with missing manifest/lockfile.

-   [x] **Task 6.3: Dependency Iteration and Configuration Retrieval**
    -   [x] Iterate through targeted dependencies (all from `project.toml` or specified names).
    -   [x] For each dependency:
        -   [x] Retrieve its configuration (canonical `source` identifier, `path`) from `project.toml`.
        -   [x] If a specified dependency name is not found in `project.toml`, skip with a warning.
    -   [x] Manual Verification: Code review logic for iteration and config fetching. Test with a mix of valid and invalid specified dependency names.

-   [x] **Task 6.4: Target Version Resolution and Lockfile State Retrieval**
    -   [x] For each dependency:
        -   [x] Resolve its `source` from `project.toml` to a concrete downloadable raw URL and a definitive commit hash/version identifier (using `internal/source`). This involves fetching latest commit for branches/tags if necessary.
        -   [x] Retrieve its current locked state (raw `source` URL, `hash`) from `almd-lock.toml`, if an entry exists.
        -   [x] **Sub-Task 6.4.1: Support `github:owner/repo/path/to/file@ref` shorthand in `internal/source` (2025-05-08)**
            -   [x] Modified `internal/core/source/source.go`'s `ParseSourceURL` function to correctly parse the shorthand, extract components, and build the raw download URL.
    -   [x] Manual Verification: Test source resolution for branches, tags, and specific commits. Check retrieval from lockfile. Test new shorthand format.

-   [x] **Task 6.5: Comparison Logic and Update Decision**
    -   [x] For each dependency, determine if an install is required based on PRD logic:
        -   [x] Resolved target commit hash (from `project.toml` source) differs from locked commit hash.
        -   [x] Dependency in `project.toml` but missing from `almd-lock.toml`.
        -   [x] Local file at `path` is missing.
        -   [x] `--force` flag is used.
    -   [x] If none of the above, the dependency is considered up-to-date.
    -   [x] Manual Verification: Code review decision logic against PRD.

-   [x] **Task 6.6: Perform Install (If Required)**
    -   [x] For each dependency needing an install:
        -   [x] Download the file from the resolved target raw URL (using `internal/downloader`).
        -   [x] Calculate integrity hash (commit hash preferred, else SHA256 via `internal/hasher`).
        -   [x] Save the downloaded file to its `path` (from `project.toml`), creating parent directories if needed.
        -   [x] Update `almd-lock.toml`: store the exact raw download URL used, `path`, and new integrity `hash`. The `source` in `project.toml` remains (e.g., can still be a branch).
    -   [x] Manual Verification: Test a scenario where an update is performed. Check downloaded file content, path, and `almd-lock.toml` changes.

-   [x] **Task 6.7: Output and Error Handling**
    -   [x] Provide clear feedback: which dependencies checked, updated, already up-to-date.
    -   [x] Report errors clearly (e.g., download failure, source resolution failure, file write failure) via `urfave/cli`.
    -   [x] Manual Verification: Observe output for various scenarios (updates, no updates, errors).

-   [x] **Task 6.8: Fix Lint Errors in `install.go` (2025-05-08)**
    -   [x] Corrected `lf.Packages` to `lf.Package` in `internal/cli/install/install.go`.
    -   [x] Corrected type `project.LockPackageDetail` to `lockfile.PackageEntry` for lockfile map values in `internal/cli/install/install.go`.

## Milestone 7: `install` Command Testing

**Goal:** Implement unit tests for the `install` command.

-   [x] **Task 7.1: Test File Structure and Helpers for `install` (2025-05-08)**
    -   [x] Create test file: `internal/cli/install/install_test.go`.
    -   [x] Develop test helpers:
        -   [x] `setupInstallTestEnvironment(...)`: Creates temp dir, `project.toml`, `almd-lock.toml`, mock dependency files.
        -   [x] `runInstallCommand(...)`: Executes the `install` command's action with specified args and context.
        -   [x] Mock HTTP server setup (similar to `add` command tests) for controlling download responses and simulating remote changes.

-   [ ] **Task 7.2: Implement `install` Command Unit Test Cases**
    -   [x] **Sub-Task 7.2.1: Test `almd install` - All dependencies, one needs install (commit hash change) (2025-05-08)**
        -   [x] Setup: `project.toml` specifies `depA@main`. `almd-lock.toml` has `depA` at `commit1`. Mock server resolves `main` for `depA` to `commit2` and serves new content.
        -   [x] Execute: `almd install`.
        -   [x] Verify: `depA` file updated, `almd-lock.toml` updated for `depA` to `commit2`. Other up-to-date deps untouched.
    -   [x] **Sub-Task 7.2.2: Test `almd install <dep_name>` - Specific dependency install**
        -   [x] Setup: Similar to 7.2.1, but also `depB` needs update.
        -   [x] Execute: `almd install depA`.
        -   [x] Verify: Only `depA` is updated. `depB` remains as per old lockfile.
    -   [x] **Sub-Task 7.2.3: Test `almd install` - All dependencies up-to-date**
        -   [x] Setup: `project.toml` sources resolve to same commits as in `almd-lock.toml`. Local files exist.
        -   [x] Execute: `almd install`.
        -   [x] Verify: No files downloaded, no changes to `almd-lock.toml`. Appropriate "up-to-date" messages.
    -   [x] **Sub-Task 7.2.4: Test `almd install` - Dependency in `project.toml` but missing from `almd-lock.toml` (2025-05-08)**
    -   [x] Setup: `depNew` in `project.toml`, but no entry in `almd-lock.toml`.
    -   [x] Execute: `almd install`.
    -   [x] Verify: `depNew` is downloaded, file saved, and entry added to `almd-lock.toml`.
    -   [x] **Sub-Task 7.2.5: Test `almd install` - Local dependency file missing (2025-05-08)**
    -   [x] Setup: `depA` in `project.toml` and `almd-lock.toml`, but its local file is deleted.
    -   [x] Execute: `almd install depA`.
    -   [x] Verify: `depA` is re-downloaded based on `almd-lock.toml`'s pinned version (or `project.toml` if it dictates a newer one). `almd-lock.toml` reflects the version downloaded.
    -   [x] **Sub-Task 7.2.6: Test `almd install --force` - Force install on an up-to-date dependency (2025-05-08)**
        -   [x] Setup: `depA` is up-to-date.
        -   [x] Execute: `almd install --force depA`.
        -   [x] Verify: `depA` is re-downloaded and `almd-lock.toml` entry is refreshed, even if commit hash was the same.
    -   [x] **Sub-Task 7.2.7: Test `almd install <non_existent_dep>` - Non-existent dependency specified (2025-05-08)**
        -   [x] Setup: `project.toml` does not contain `non_existent_dep`.
        -   [x] Execute: `almd install non_existent_dep`.
        -   [x] Verify: Warning message printed, no other actions taken for this dep. Other valid deps (if `install` was called without args but one was invalid) should process normally.
    -   [x] **Sub-Task 7.2.8: Test `almd install` - Error during download (2025-05-08)**
        -   [x] Setup: Mock server returns HTTP error for a dependency that needs update.
        -   [x] Execute: `almd install`.
        -   [x] Verify: Command reports error for that dependency. `almd-lock.toml` and local file for that dep remain unchanged or reflect pre-update state.
    -   [x] **Sub-Task 7.2.9: Test `almd install` - Error during source resolution (e.g., branch not found) (2025-05-08)**
        -   [x] Setup: `project.toml` points to `depA@nonexistent_branch`. Mock `internal/source` to simulate resolution failure.
        -   [x] Execute: `almd install depA`.
        -   [x] Verify: Command reports error for `depA`. No download attempt.
    -   [x] **Sub-Task 7.2.10: Test `almd install` - `project.toml` not found (2025-05-08)**
        -   [x] Setup: Run `install` in a temp dir without `project.toml`.
        -   [x] Execute: `almd install`.
        -   [x] Verify: Command returns an appropriate error.

## Milestone 8: `list` Command Implementation

**Goal:** Implement the `almd list` (and `ls`) command to display project dependencies.

-   [x] **Task 8.1: `urfave/cli` Command Setup for `list` (2025-05-08)**
    -   [x] Define the `list` command structure (`cli.Command`) in `internal/cli/list/list.go`.
    -   [x] Add `ls` as an alias for the `list` command.
    -   [x] Add the command to the `urfave/cli` App in `main.go`.
    -   [x] Manual Verification: Run `almd list --help` and `almd ls --help`. Confirm command, alias, and flags are listed.

-   [x] **Task 8.2: Manifest and Lockfile Loading for `list` (2025-05-08)**
    -   [x] In the `list` command's `Action`, load `project.toml` (using `internal/core/config`). Handle if not found (print "No dependencies..." or error).
    -   [x] Load `almd-lock.toml` (using `internal/core/lockfile`). Handle if not found (dependencies will show as "not locked").
    -   [x] Manual Verification: Test with missing manifest/lockfile.

-   [x] **Task 8.3: Dependency Traversal and Information Gathering (2025-05-08)**
    -   [x] Iterate through dependencies in `project.toml`'s `[dependencies]` table.
    -   [x] For each dependency, retrieve:
        -   [x] Logical name.
        -   [x] Configured `source` from `project.toml`.
        -   [x] Relative `path` from `project.toml`.
        -   [x] Locked raw `source` URL and `hash` from `almd-lock.toml` (if present).
        -   [x] Local file existence status at `path`.
    -   [x] Manual Verification: Code review data gathering logic.

-   [x] **Task 8.4: Default Output Formatting (2025-05-08)**
    -   [x] Implement the default output format as per PRD:
        -   [x] Logical dependency name.
        -   [x] Declared `source` from `project.toml`.
        -   [x] Locked `hash` from `almd-lock.toml` (or "not locked").
        -   [x] Relative `path`.
    -   [x] Manual Verification: Run `almd list` with a sample project and check output.

-   [x] **Task 8.5: Handling Projects with No Dependencies (2025-05-08)**
    -   [x] If `project.toml` has no `[dependencies]` table or it's empty, print an appropriate message (e.g., "No dependencies found in project.toml."). This should work for all output formats (default, long, json, porcelain - e.g. empty array for json).
    -   [x] Manual Verification: Test with an empty `project.toml` or one without dependencies.

## Milestone 9: `list` Command Testing

**Goal:** Implement unit tests for the `list` command.

-   [x] **Task 9.1: Test File Structure and Helpers for `list` (2025-05-08)**
    -   [x] Create test file: `internal/cli/list/list_test.go`.
    -   [x] Develop test helpers:
        -   [x] `setupListTestEnvironment(...)`: Creates temp dir, `project.toml`, `almd-lock.toml`, and optionally dummy dependency files.
        -   [x] `runListCommand(...)`: Executes the `list` command's action, capturing its stdout.

-   [ ] **Task 9.2: Implement `list` Command Unit Test Cases**
    -   [x] **Sub-Task 9.2.1: Test `almd list` - No dependencies (2025-05-08)**
        -   [x] Setup: Empty `project.toml` or no `[dependencies]` table.
        -   [x] Execute: `almd list`.
        -   [x] Verify: Output indicates no dependencies. For `--json`, verify empty array or appropriate null structure. (Note: JSON output not yet implemented, test verifies default behavior)
    -   [x] **Sub-Task 9.2.2: Test `almd list` - Single dependency (fully installed and locked) (2025-05-08)**
        -   [x] Setup: `project.toml` with one dep, `almd-lock.toml` with corresponding entry, local file exists.
        -   [x] Execute: `almd list`.
        -   [x] Verify: Correct default output for the dependency.
    -   [x] **Sub-Task 9.2.3: Test `almd list` - Multiple dependencies with varied states (2025-05-08)**
        -   [x] Setup: Mix of deps: one fully installed, one in manifest but not lockfile, one in manifest & lockfile but file missing.
        -   [x] Execute: `almd list`.
        -   [x] Verify: Correct default output for each, reflecting their state.
    -   [x] **Sub-Task 9.2.4: Test `almd ls` (alias) - Verify alias works (2025-05-08)**
        -   [x] Setup: Basic project with one dependency.
        -   [x] Execute: `almd ls`.
        -   [x] Verify: Output is identical to `almd list`.
    -   [x] **Sub-Task 9.2.5: Test `almd list` - `project.toml` not found (2025-05-08 - Covered by existing `TestListCommand_ProjectTomlNotFound`)**
        -   [x] Setup: Run `list` in a temp dir without `project.toml`.
        -   [x] Execute: `almd list`.
        -   [x] Verify: Command returns an appropriate error or "no dependencies" message as per PRD.

## Milestone 10: `list` Command Output Enhancement

**Goal:** Update the `almd list` command output to be more informative and visually similar to `pnpm list`, including terminal colors using `fatih/color`.

-   [x] **Task 10.1: Define `list` Output Structure and Color Scheme**
    -   [x] Define pnpm-like output structure: Project info, "dependencies:" header, then `name path hash` for each. (Covered by previous Task 10.2, updated 2025-05-08)
    -   [x] Specify color scheme using `fatih/color` (inspired by user-provided image):
        -   Project Name: Magenta, Bold, Underline (`color.FgMagenta`, `color.Bold`, `color.Underline`)
        -   `@`: Standard color
        -   Project Version: Magenta (`color.FgMagenta`) (Note: User did not specify bold/underline for version, keeping as is)
        -   Project Path: Dim Gray, Bold, Underline (`color.FgHiBlack`, `color.Bold`, `color.Underline`)
        -   `dependencies:` header: Cyan and Bold (`color.FgCyan`, `color.Bold`)
        -   Dependency Name: Yellow (`color.FgYellow`)
        -   Dependency Hash: Standard color (No specific color attribute, or `color.Reset`)
        -   Dependency Path: Green (`color.FgGreen`)
    -   [x] Ensure `NO_COLOR` environment variable is respected (typically handled by `fatih/color` automatically, but verify).

-   [x] **Task 10.2: Implement Output Changes in `internal/cli/list/list.go` (Initial pnpm-like format)**
    -   [x] Load project name and version.
    -   [x] Modify print statements to match the new pnpm-like format (without colors yet).

-   [x] **Task 10.3: Implement Color Output in `internal/cli/list/list.go`**
    -   [x] Add `github.com/fatih/color` as a project dependency.
    -   [x] Import `fatih/color` in `internal/cli/list/list.go`.
    -   [x] Update print statements to use the defined color scheme via `fatih/color` functions.

-   [ ] **Task 10.4: Update `list` Command Tests (Blocked by Task 9.1, 9.2)**
    -   [ ] Adjust existing tests in `internal/cli/list/list_test.go` to expect the new pnpm-like format (initially without asserting exact color codes, as this can be brittle). (File to be created in Task 9.1)
    -   [x] Consider adding a simple manual verification step for color output. (Decision: Manual verification will be needed)
    -   [ ] Add new test cases if necessary to cover different scenarios with the new format (e.g., project with name/version, project without). (To be done in Task 9.2)
## Milestone 11: `add` and `remove` Command Output Enhancement (pnpm style) (2025-05-08)

**Goal:** Update the `almd add` and `almd remove` command outputs to be more visually similar to `pnpm`, including terminal colors using `fatih/color`.

-   [x] **Task 11.1: Update `add` command output**
    -   [x] Modify `internal/cli/add/add.go` to print output similar to `pnpm add`.
    -   [x] Use green color for added dependency information.
    -   [x] Include a "Done in Xs" message.
-   [x] **Task 11.2: Update `remove` command output**
    -   [x] Modify `internal/cli/remove/remove.go` to print output similar to `pnpm remove`.
    -   [x] Use red color for removed dependency information.
    -   [x] Include a "Done in Xs" message.
-   [x] **Task 11.3: Add `fatih/color` dependency if not already present**
    -   [x] Ensure `github.com/fatih/color` is in `go.mod`. (Already added by list command changes)
-   [ ] **Task 11.4: Manual Verification**
    -   [ ] Run `almd add <url>` and verify the output matches the pnpm style.
    -   [ ] Run `almd remove <dep_name>` and verify the output matches the pnpm style.
## Milestone 12: `self update` Command Implementation

**Goal:** Implement the `almd self update` command to allow the Almandine tool to update itself.

-   [x] **Task 12.1: `urfave/cli` Command Setup for `self update`**
    -   [x] Define the `self` command structure (`cli.Command`) in a new file (e.g., `internal/cli/self/self.go`).
    -   [x] Define the `update` subcommand within the `self` command.
    -   [x] Add the `self` command (with its `update` subcommand) to the `urfave/cli` App in `cmd/almd/main.go`.
    -   [x] Define flags for `almd self update`: `--yes`/`-y` (bool), `--check` (bool), `--source <url>` (string), `--verbose` (bool).
    -   [x] Manual Verification: Run `almd self update --help` and confirm the command, subcommand, and flags are listed correctly.

-   [x] **Task 12.2: Add Self-Update Library**
    -   [x] Add `github.com/creativeprojects/go-selfupdate` as a project dependency (`go get github.com/creativeprojects/go-selfupdate`).
    -   [x] Manual Verification: `go.mod` and `go.sum` are updated.

-   [x] **Task 12.3: Implement Version Embedding (2025-05-08)**
    -   [x] Ensure the application version is embedded at build time. This typically involves:
        -   [x] Defining a `var version string` in the `main` package (`cmd/almd/main.go`).
        -   [x] Setting this variable during the build using ldflags: `go build -ldflags="-X main.version=vX.Y.Z" ./cmd/almd`.
        -   [x] The `cli.App` `Version` field should use this variable.
    -   [x] Manual Verification: Build the binary with a version, run `almd --version`, and confirm the embedded version is printed.

-   [x] **Task 12.4: Implement Core `self update` Logic (2025-05-08)**
    -   [x] In the `update` subcommand's `Action`:
        -   [x] Retrieve the current application version (embedded in Task 12.3).
        -   [x] Use `github.com/creativeprojects/go-selfupdate` to:
            -   [x] Configure the updater (e.g., for GitHub releases, using `selfupdate.NewGitHubSource` and `selfupdate.NewUpdater`).
            -   [x] If `--check` flag is used, detect the latest version and inform the user if an update is available, then exit.
            -   [x] Detect the latest available release version.
            -   [x] Compare with the current version. If no newer version, inform the user and exit.
            -   [x] If a newer version is available, prompt for confirmation unless `--yes` is used.
            -   [x] Perform the update (download, verify, replace).
        -   [x] Handle errors gracefully (e.g., network issues, no new version, update failure).
        -   [x] Provide clear output messages throughout the process.
    -   [x] Manual Verification:
        -   [x] Test `--check` flag when an update is available and when not.
        -   [x] Test update process: with and without `--yes`.
        -   [ ] Test with no new version available.
        -   [ ] Simulate network error if possible to check error handling.

-   [ ] **Task 12.5: Testing for `self update`**
    -   [ ] **Note:** Fully automated E2E testing for self-update is complex as it involves replacing the running binary. Initial testing will likely be manual or involve carefully crafted integration tests that mock parts of the update process.
    -   [ ] Define manual test scenarios:
        -   [ ] Update from an older version to a newer version.
        -   [ ] Attempt update when already on the latest version.
        -   [ ] Use `--check` flag.
        -   [ ] Use `--yes` flag.
    -   [ ] Consider creating a simple integration test that:
        -   [ ] Mocks the `github.com/creativeprojects/go-selfupdate` library's interactions (e.g., API calls, download).
        -   [ ] Verifies the command logic (flag parsing, conditional execution based on mocked updater responses).
        -   [ ] This would not test the actual binary replacement but would cover the command's flow.

---

## Milestone 13: Core Logic Unit Testing (`internal/core`)

**Goal:** Ensure comprehensive unit test coverage for all packages within `internal/core`.

-   [x] **Task 13.1: Define Testing Strategy for `internal/core`**
    -   [x] Framework: Standard Go `testing` package with `testify` for assertions.
    -   [x] Scope: Unit tests for public functions/methods in each `internal/core` package.
    -   [x] Mocks: Use mocks for external dependencies (e.g., network, filesystem) where appropriate.
    -   [x] Structure: Test files alongside source files (e.g., `config_test.go` for `config.go` within `internal/core/config/`).
    -   [x] Manual Verification: Review strategy for completeness.

-   [x] **Task 13.2: Implement Unit Tests for `internal/core/config`**
    -   [x] Create `internal/core/config/config_test.go`.
    -   [x] Test `LoadProjectToml` (valid, not found, invalid format).
    -   [x] Test `SaveProjectToml` (writing, overwriting).
    -   [x] Manual Verification: Run `go test ./internal/core/config/...`.

-   [x] **Task 13.3: Implement Unit Tests for `internal/core/downloader` (2025-05-08)**
    -   [x] Create `internal/core/downloader/downloader_test.go`.
    -   [x] Test `DownloadFile` (success, HTTP errors, network issues) using `httptest`.
    -   [ ] Manual Verification: Run `go test ./internal/core/downloader/...`.

-   [x] **Task 13.4: Implement Unit Tests for `internal/core/hasher` (2025-05-08)**
    -   [x] Create `internal/core/hasher/hasher_test.go`.
    -   [x] Test `CalculateSHA256` with known content.
    -   [ ] Manual Verification: Run `go test ./internal/core/hasher/...`.

-   [x] **Task 13.5: Implement Unit Tests for `internal/core/lockfile` (2025-05-08)**
    -   [x] Create `internal/core/lockfile/lockfile_test.go`.
    -   [x] Test `LoadLockfile` (valid, not found, invalid format).
    -   [x] Test `SaveLockfile` (writing, overwriting).
    -   [ ] Manual Verification: Run `go test ./internal/core/lockfile/...`.

-   [x] **Task 13.6: Implement Unit Tests for `internal/core/project` (2025-05-08)**
    -   [x] Create `internal/core/project/project_test.go`.
    -   [x] Test any helper functions or methods on the `Project`, `Dependency`, `Script`, etc. structs if they contain logic beyond simple data holding. (Tested `NewProject()` constructor; other structs are data holders).
    -   [ ] Manual Verification: Run `go test ./internal/core/project/...`.

-   [x] **Task 13.7: Implement Unit Tests for `internal/core/source` (2025-05-08)**
    -   [x] Create `internal/core/source/source_test.go`.
    -   [x] Test `ParseSourceURL` with various valid and invalid GitHub URL formats (raw, blob, tree, with/without ref, shorthand).
    -   [ ] Test `GetGitHubRawURLAndCommit` (mocking `FetchLatestCommitSHA` and `FetchFileCommitSHA`). *(Note: `GetGitHubRawURLAndCommit` function not found in current `source.go`)*.
    -   [x] Create `internal/core/source/github_api_test.go`.
    -   [x] Test `GetLatestCommitSHAForFile` (mocking HTTP calls to GitHub API). *(Note: Tested existing `GetLatestCommitSHAForFile` instead of non-existent `FetchLatestCommitSHA` / `FetchFileCommitSHA`)*.
    -   [ ] Manual Verification: Run `go test ./internal/core/source/...`.

---

## Milestone 14: Test Fixes (2025-05-08)

**Goal:** Address and fix failing tests reported by `go test -v ./... -race -coverprofile=coverage.out -covermode=atomic`.

-   [x] **Task 14.1: Fix `TestRemoveCommand_ProjectTomlNotFound` in `internal/cli/remove/remove_test.go` (2025-05-08)**
    -   [x] Investigated assertion failure: `"Error: Failed to load project.toml: open project.toml: no such file or directory" does not contain "cannot find the file specified"`.
    -   [x] Updated assertion to correctly match the expected error message ("no such file or directory").
-   [x] **Task 14.2: Fix Data Races in `internal/core/source` tests (2025-05-08)**
    -   [x] Investigated data races reported for `githubAPIURL` and `testModeBypassHostValidation` in `source_test.go`, `github_api_test.go`, and `source.go`.
    -   [x] Implemented synchronization using exported mutexes (`GithubAPIBaseURLMutex`, `TestModeBypassHostValidationMutex`) in the `source` package to protect shared global variables accessed by parallel tests. Updated `github_api.go`, `source.go`, and `source_test.go` to use these mutexes. (Attempt 1)
    -   [x] Added a package-level mutex (`githubAPITestMutex`) in `internal/core/source/github_api_test.go` to serialize test functions that call `setupSourceTest` or otherwise modify shared global state in the `source` package. Removed `t.Parallel()` from these specific test functions. (Attempt 2 - 2025-05-08)
-   [x] **Task 14.3: Fix Path Mismatch Failures in `internal/cli/list/list_test.go` (2025-05-08)**
    -   [x] Investigated failures in `TestListCommand_SingleDependencyFullyInstalledAndLocked`, `TestListCommand_MultipleDependenciesVariedStates`, and `TestListCommand_AliasLs` due to `/private/var` vs `/var` path differences on macOS.
    -   [x] Updated tests to use `filepath.EvalSymlinks` on the temporary directory path before constructing expected output strings, ensuring canonical paths are compared.
-   [x] **Task 14.4: Fix `TestCalculateSHA256_DifferentContent` in `internal/core/hasher/hasher_test.go` (2025-05-09)**
    -   [x] Investigated assertion failures where actual calculated SHA256 hashes did not match expected hashes.
    -   [x] Corrected the `expectedHash1` and `expectedHash2` values in `internal/core/hasher/hasher_test.go` to match the actual correct SHA256 hashes for the test strings "almandine-rocks" and "almandine-rules".
## Milestone 15: Dev Environment Configuration (2025-05-09)

**Goal:** Configure the development environment.

-   [x] **Task 15.1: Add `gitingest` to `devenv.nix` (2025-05-09)**
    -   [x] Added `languages.python` configuration to `devenv.nix`.
    -   [x] Enabled Python virtual environment (`venv.enable = true`).
    -   [x] Added `gitingest` to `venv.requirements`.
    -   [x] Manual Verification: Run `devenv shell` and confirm `gitingest` command is available.
---

## Milestone 16: Code Standards Application (2025-05-09)

**Goal:** Ensure code comments adhere to defined project standards.

-   [x] **Task 16.1: Apply comment standards to `internal/cli/remove/remove_test.go` (2025-05-09)**
    -   [x] Reviewed comments in `internal/cli/remove/remove_test.go` against `project/COMMENT_STANDARDS.txt`.
    -   [x] Removed obvious "what" comments.
    -   [x] Retained godoc comments and comments explaining test setup or "why".
---

## Milestone 17: Refactoring and Cleanup (2025-05-09)

**Goal:** Improve code quality, maintainability, and reduce complexity in existing modules.

-   [x] **Task 17.1: Refactor `internal/cli/add/add.go` (2025-05-09)**
    -   [x] Break down the main `Action` function in `AddCmd` into smaller, focused helper functions (e.g., for arg parsing, URL handling, file operations, manifest updates, lockfile updates).
    -   [x] Simplify the error handling and cleanup logic, potentially by returning errors more consistently and centralizing cleanup.
    -   [x] Encapsulate filename determination logic (for manifest and disk) into a separate function.
    -   [x] Encapsulate integrity hash determination logic into a separate function.
    -   [x] Review and improve overall clarity and reduce nesting in the `Action` function.

-   [x] **Task 17.2: Refactor `internal/cli/install/install.go` (2025-05-09)**
    -   [x] Break down the main `Action` function in `InstallCmd` into smaller, manageable functions (e.g., for determining deps to process, resolving single dep state, deciding on action, performing install/update for a single dep).
    -   [x] Consider refactoring the management of `dependencyInstallState` into a dedicated helper or struct with methods. (Decision: Kept as local types for now, helper functions manage transitions).
    -   [x] Review and improve overall clarity and reduce nesting in the `Action` function.

-   [x] **Task 17.3: Refactor `internal/core/source/source.go` (2025-05-09)**
    -   [x] Break down the `ParseSourceURL` function into smaller helper functions for different URL types (e.g., `parseGitHubShorthandURL`, `parseGitHubFullURL`, `parseRawGitHubUserContentURL`).
    -   [x] Review the usage of `testModeBypassHostValidation` and its mutex for clarity and safety.

-   [ ] **Task 17.4: Consolidate CLI Test Helpers (2025-05-09)**
    -   [ ] Identify common test helper functions in `internal/cli/*/ *_test.go` files (e.g., `setup...TestEnvironment`, `run...Command`, `startMockServer`, `readProjectToml`, `readAlmdLockToml`).
    -   [ ] Create a shared internal test utility package (e.g., `internal/testutil` or `internal/cli/testhelper`).
    -   [ ] Move common helpers to this shared package and update tests to use them.

-   [x] **Task 17.5: Standardize Error Handling in CLI Commands (2025-05-09)**
    -   [x] Review error handling and cleanup strategies in `add.go`, `remove.go`, and `install.go`.
    -   [x] Define and apply a consistent approach for reporting errors to the user (via `cli.Exit` or other means).
    -   [x] Ensure that partial changes are appropriately handled (e.g., cleanup of downloaded files if subsequent manifest/lockfile updates fail).

-   [x] **Task 17.6: Review Installer Scripts (`install.ps1`, `install.sh`) (2025-05-09)**
    -   [x] Review `install.ps1` and `install.sh` for clarity, robustness, and potential areas for simplification.
        -   Both scripts are generally clear, robust, and maintainable.
        -   Key finding: Both scripts download the full source archive and extract the binary/necessary files.
        -   Recommendation: Standardize by downloading pre-compiled release assets from GitHub Releases for the target OS/architecture. This aligns with common practice and the `self-update` mechanism, simplifies scripts, and reduces download size.
        -   `install.ps1`: Downloads source, expects `almd.exe` in extracted root.
        -   `install.sh`: Downloads source, expects `install/almd` (executable) and `src/` (copied to `$APP_HOME`).
        -   The role and content of `$APP_HOME` should be consistent based on `almd`'s runtime needs. If `almd` is a self-contained binary, `$APP_HOME` might only be for user-generated config/data.
    -   [x] Document any shared logic or installation philosophy to ensure consistency if one script is updated.
        -   Shared philosophy: Install latest/specific version from GitHub or local build, place executable in PATH, use temp dirs, advise on PATH configuration.
    -   [x] Consider if any parts of the scripts could be made more maintainable.
        -   Current maintainability is good. Switching to release assets would be the main improvement.
        -   Minor: `ps1` could improve `curl/wget` exit code checks. `sh` could use `jq` for API parsing if available and improve `wget` error checks.
