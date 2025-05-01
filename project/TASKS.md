# Task Checklist: Almandine Package Manager

**Purpose:** Tracks tasks, milestones, and backlog for implementing the `add` command and its associated E2E testing infrastructure for the Almandine Lua package manager. Each task includes verification steps.

**Multiplatform Policy:** All tasks, implementations, and verifications MUST consider cross-platform compatibility (Linux, macOS, and Windows) unless otherwise specified. Contributors (including AI) are required to design, implement, and test with multiplatform support as a baseline expectation. Any platform-specific logic must be clearly documented and justified in both code and task notes.

---

## CLI Tool Name

- The CLI executable is called `almd` (short for Almandine).
- All documentation, usage, and examples should refer to the CLI as `almd` (not `almandine`).

---

## Milestone 1: `add` Command Implementation & Verification

**Goal:** Ensure `src/modules/add.lua` correctly implements the functionality defined in the PRD and address any gaps.

- [ ] **Task 1.1: Review Existing `add` Implementation vs PRD**
    - [ ] AI/Developer: Manually compare the *current* code in `src/modules/add.lua` against the requirements detailed in PRD sections 2.1 (`add` command description), 4 (`project.lua`, `almd-lock.lua`), and 1.1 (Dependencies - HTTP client decision).
    - [ ] Identify any discrepancies, missing features, or incorrect behaviors based *strictly* on the PRD. Document these gaps.
    - [ ] Manual Verification: Checklist of PRD requirements vs implemented features is created.

- [ ] **Task 1.2: Implement Identified Gaps in `add` Command**
    - [ ] Based on Task 1.1, implement any missing functionality in `src/modules/add.lua`. This might include:
        - [ ] Correct argument parsing (`<url>`, `-d`, `-n`).
        - [ ] Correct GitHub URL parsing (commit hash vs branch name).
        - [ ] Conversion to raw GitHub URL for download.
        - [ ] Cross-platform file download mechanism (confirming approach: LuaSocket vs shell out).
        - [ ] Target directory creation.
        - [ ] Correct file saving (respecting `-n` for filename).
        - [ ] Accurate reading/updating of `project.lua` (correct key/value format).
        - [ ] Accurate reading/updating of `almd-lock.lua` (correct path, source, hash type - commit vs sha256).
        - [ ] sha256 hash calculation when needed.
        - [ ] Graceful error handling and user messaging for failures (download, file access, invalid manifest).
    - [ ] Manual Verification: Code review confirms implementation matches PRD requirements identified in Task 1.1. Cross-platform considerations are addressed.

- [ ] **Task 1.3: Integrate `add` into `main.lua`**
    - [ ] Ensure `src/main.lua` correctly parses the `add` command (and `i` alias).
    - [ ] Ensure arguments (`<url>`, `-d`, `-n`) are correctly passed to the `add` module.
    - [ ] Manual Verification: Run `almd add --help` (or similar) and verify basic command recognition works. Check argument parsing logic in `main.lua`.

## Milestone 2: E2E Testing Infrastructure (Scaffolding)

**Goal:** Create the necessary helper utilities for running E2E tests in isolated environments.

- [ ] **Task 2.1: Implement Test Scaffolding Helper (`scaffold.lua`)**
    - [ ] Create `src/spec/e2e/helpers/scaffold.lua`.
    - [ ] Implement `scaffold.create_sandbox_project()`: Creates a unique temporary directory for a test. Returns the path and a cleanup function.
    - [ ] Implement `cleanup_func()`: Deletes the temporary directory and its contents.
    - [ ] Implement `scaffold.init_project_file(sandbox_path, initial_data)`: Creates a basic `project.lua` in the sandbox.
    - [ ] Implement `scaffold.run_almd(sandbox_path, args_table)`: Executes the `almd` command (via `src/main.lua` or the wrapper script) targeting the sandbox directory, capturing success/failure status and output (stdout/stderr). Must work cross-platform.
    - [ ] Implement `scaffold.read_project_lua(sandbox_path)`: Reads and parses the `project.lua` file from the sandbox. Returns the Lua table. Handles file-not-found errors.
    - [ ] Implement `scaffold.read_lock_lua(sandbox_path)`: Reads and parses the `almd-lock.lua` file. Returns the Lua table. Handles file-not-found errors.
    - [ ] Implement `scaffold.file_exists(file_path)`: Checks if a file exists at the given absolute path.
    - [ ] Implement `scaffold.read_file(file_path)`: Reads the content of a file. (Optional, but useful for checking downloaded content).
    - [ ] Manual Verification: Code review of the scaffold helper. Test helper functions individually if possible. Ensure cleanup works reliably.

## Milestone 3: E2E Tests for `add` Command

**Goal:** Implement the specific E2E test cases for the `add` command using Busted and the scaffolding helper.

- [ ] **Task 3.1: Create `add_spec.lua` Structure**
    - [ ] Create `src/spec/e2e/modules/add_spec.lua`.
    - [ ] Set up the `describe` block.
    - [ ] Implement `before_each` to call `scaffold.create_sandbox_project()` and `scaffold.init_project_file()`.
    - [ ] Implement `after_each` to call the `cleanup_func()`.
    - [ ] Manual Verification: Run the empty spec file with `busted`; ensure setup/teardown execute without errors.

- [ ] **Task 3.2: Implement E2E Test: Add via Commit Hash (Default Path)**
    - [ ] Implement the `it` block corresponding to PRD E2E Example 1.
    - [ ] Use `scaffold.run_almd` to execute the command.
    - [ ] Use `scaffold.file_exists`, `scaffold.read_project_lua`, `scaffold.read_lock_lua` and Busted `assert` functions to verify:
        - File downloaded to `lib/shove.lua`.
        - `project.lua` contains `dependencies.shove` with the correct source string.
        - `almd-lock.lua` contains `package.shove` with correct `path`, `source`, and `hash` (starting with `commit:`).
    - [ ] Manual Verification: Run `busted src/spec/e2e/modules/add_spec.lua`; confirm this test passes and performs the correct checks.

- [ ] **Task 3.3: Implement E2E Test: Add via Commit Hash (Custom Path `-d`)**
    - [ ] Implement the `it` block corresponding to PRD E2E Example 2.
    - [ ] Verify:
        - File downloaded to `src/engine/lib/shove.lua`.
        - `project.lua` contains `dependencies.shove` with correct structure (e.g., table with `source` and `path`).
        - `almd-lock.lua` contains `package.shove` with the custom `path`.
    - [ ] Manual Verification: Run `busted`; confirm test passes.

- [ ] **Task 3.4: Implement E2E Test: Add via Commit Hash (Custom Path `-d`, Custom Name `-n`)**
    - [ ] Implement the `it` block corresponding to PRD E2E Example 3.
    - [ ] Verify:
        - File downloaded to `src/engine/lib/clove.lua`.
        - `project.lua` contains `dependencies.clove` (using the new name) with correct structure/path.
        - `almd-lock.lua` contains `package.clove` with the custom `path` and new name.
    - [ ] Manual Verification: Run `busted`; confirm test passes.

- [ ] **Task 3.5: Implement E2E Test: Add via Branch Name (SHA256 Hash)**
    - [ ] Implement the `it` block corresponding to PRD E2E Example 4.
    - [ ] Verify:
        - File downloaded to `lib/shove.lua`.
        - `project.lua` contains `dependencies.shove`.
        - `almd-lock.lua` contains `package.shove` with `hash` starting with `sha256:`.
    - [ ] Manual Verification: Run `busted`; confirm test passes.

- [ ] **Task 3.6: Implement E2E Test: Add Non-Existent File (Error Case)**
    - [ ] Implement the `it` block corresponding to PRD E2E Example 5.
    - [ ] Verify:
        - `scaffold.run_almd` returns failure status.
        - Output contains an informative error message.
        - The target file does *not* exist.
        - `project.lua` and `almd-lock.lua` are unchanged (or don't contain the failed dependency).
    - [ ] Manual Verification: Run `busted`; confirm test passes and correctly checks for failure and lack of side effects.

---

## Analysis & Next Steps

### Potentially Missing Test Cases for `add`

Based on the initial set, here are areas where more E2E tests would improve robustness:

1.  **Idempotency/Re-adding:**
    * Run `almd add <url>` twice for the same URL. Expected: Should it succeed silently (no change), update if the remote changed (e.g., branch `main`), or error? Define and test the desired behavior.
    * Run `almd add <url1>` then `almd add <url2> -n name1` where `url2` downloads a file that would overwrite the file from `url1`. Define and test behavior (error, overwrite, prompt?).
2.  **Overwriting Conflicts:**
    * Test adding a dependency `foo` when `lib/foo.lua` already exists but wasn't added by `almd`.
    * Test adding with `-n bar` when `lib/bar.lua` already exists.
3.  **Manifest/Lockfile Corruption:**
    * Run `almd add` when `project.lua` exists but is invalid Lua syntax.
    * Run `almd add` when `almd-lock.lua` exists but is invalid Lua syntax.
    * Run `almd add` when `project.lua` or `almd-lock.lua` return non-table values.
4.  **Network Failures:**
    * Simulate network errors *during* download (if possible with chosen download method). Verify partial downloads are cleaned up and manifests aren't updated.
5.  **Permissions Errors:**
    * Run `almd add` targeting a directory where the user lacks write permissions.
    * Run `almd add` when `project.lua` or `almd-lock.lua` are read-only.
6.  **URL Variations:**
    * Test different valid GitHub URL formats (e.g., `github.com/user/repo/blob/TAG/path/file.lua`).
    * Test invalid/malformed URLs.
7.  **Initialization Requirement:**
    * Run `almd add` in a directory *without* a `project.lua`. Expected: Should error clearly stating the project needs initialization (`almd init`).
8.  **Case Sensitivity:** Add tests involving filenames with different casing if targeting file systems where this matters (e.g., adding `MyLib.lua` then `mylib.lua` on Windows vs Linux).

### Potential Improvements for `add` Functionality

Beyond the core requirements, consider these future enhancements:

1.  **Source Extensibility:** Design the URL parsing and downloading logic in `src/lib` (or `src/utils`) to be easily extended for other sources (GitLab, Bitbucket, generic Git URLs, plain HTTP(S) URLs, maybe even local paths `../other-project/file.lua`).
2.  **Atomic Operations:** Refactor download and manifest updates to be more atomic. E.g., download to a temporary file, verify hash, then move to the final location; update manifest tables in memory, then attempt to write the complete file. This reduces the chance of a corrupted state if the process is interrupted.
3.  **Download Progress/Feedback:** For larger files or slower connections, provide some feedback to the user during download.
4.  **Caching:** Implement a local cache for downloaded files (based on URL and commit/hash) to avoid redundant downloads.
5.  **Dry Run Mode:** Add a `--dry-run` flag to show what files would be downloaded and how manifests would change without actually performing the actions.
6.  **Confirmation Prompts:** Add an optional `-y` / `--yes` flag, and without it, prompt the user before potentially overwriting existing files or making significant changes.

*This TASKS.md outlines the immediate work. Further tasks should be added for the missing test cases and potential improvements as development progresses.*