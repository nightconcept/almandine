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

- [x] **Task 1.1: Review Existing `add` Implementation vs PRD**
    - [x] AI/Developer: Manually compare the *current* code in `src/modules/add.lua` against the requirements detailed in PRD sections 2.1 (`add` command description), 4 (`project.lua`, `almd-lock.lua`), and 1.1 (Dependencies - HTTP client decision).
    - [x] Identify any discrepancies, missing features, or incorrect behaviors based *strictly* on the PRD. Document these gaps.
    - [x] Manual Verification: Checklist of PRD requirements vs implemented features is created.

- [ ] **Task 1.2: Implement Identified Gaps in `add` Command**
    - [ ] Based on Task 1.1, implement any missing functionality in `src/modules/add.lua`. This might include:
        - [ ] Confirm/Implement Download Mechanism: Decide and implement the cross-platform download method (shell out preferred by PRD 1.1 to avoid Lua deps, vs. LuaSocket). Currently uses injected `deps.downloader.download`.
        - [ ] Clarify/Fix Default Directory: PRD 2.1/Example 1 imply default `lib/`, implementation uses `src/lib/`. Clarify intended default for user dependencies and adjust implementation if needed.
        - [ ] Align `project.lua` Structure: Implementation stores `{ url=..., path=..., [hash=...] }`. PRD examples show `github:...@hash` string or `{ source="github:...", path="..." }`. Align implementation to match PRD structure (likely the table format with `source` field).
        - [ ] Correct `almd-lock.lua` Structure & Content:
            - Add the missing `path` field to lockfile entries.
            - Ensure the `source` field in the lockfile matches the identifier used in `project.lua`.
            - Fix hashing logic (`hash_utils.hash_dependency`) to hash file *content* for sha256.
            - Implement logic to store `hash = "commit:..."` if the source URL specified a commit hash, otherwise store `hash = "sha256:..."` (using the corrected content hash).
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
    - [ ] Implement the `