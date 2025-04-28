# Almandine Package Manager – Task Checklist (TASK.md)

**Purpose:** Tracks all tasks, milestones, and backlog for the Almandine Lua package manager. Each task includes a manual verification step for running and inspecting all tests and code.

**Multiplatform Policy:** All tasks, implementations, and verifications MUST consider cross-platform compatibility (Linux, macOS, and Windows) unless otherwise specified. Contributors (including AI) are required to design, implement, and test with multiplatform support as a baseline expectation. Any platform-specific logic must be clearly documented and justified in both code and task notes.

---

## CLI Tool Name

- The CLI executable is called `almd` (short for Almandine).
- All documentation, usage, and examples should refer to the CLI as `almd` (not `almandine`).

---

## Milestone 1: Project Manifest & Initialization

- [x] **Task 1.1: Design and implement `project.lua` manifest schema**
  - [x] Define fields: `name`, `type`, `version`, `license`, `description`, `scripts`, `dependencies`.
  - [x] Manual Verification: Review schema, create sample file, and validate with test loader.

- [x] **Task 1.2: CLI command to initialize a new Almandine project**
  - [x] Implement `almd init` (creates `project.lua` with prompts).
  - [x] Create a portable shell wrapper script that finds a suitable Lua interpreter and runs `src/main.lua` with all arguments (works on macOS and Linux).
  - [x] Manual Verification: Run shell script with arguments, confirm it finds Lua and dispatches to `almd`.
  - [x] Manual Verification: Run `almd`, inspect output, ensure correct manifest generation.

- [x] **Task 1.3: Create Windows CLI wrapper script (`almd.bat`)** 
  - [x] Implement a batch script at the project root that finds a suitable Lua interpreter and runs `src/main.lua` with all arguments (works on Windows).
  - [x] Manual Verification: Run batch script with arguments, confirm it finds Lua and dispatches to `almd`.

## Milestone 2: Dependency Download & Pinning

- [x] **Task 2.1: Implement file downloader (GitHub/raw URL support)**
  - [x] Support pinning by semver or commit hash.
  - [x] Manual Verification: Download a file, verify correct version/hash is retrieved.

- [x] **Task 2.2: Implement dependency install command**
  - [x] Add CLI function to add or remove dependencies from `project.lua` (establish dependency set).
  - [x] Parse `dependencies` from `project.lua`.
  - [x] Download to correct location (e.g., `lib/`).
  - [ ] Manual Verification: Inspect downloaded files, check hashes/versions.

## Milestone 3: Lockfile Management

- [x] **Task 3.1: Design and implement `almd-lock.lua` schema**
  - [x] Track `api_version`, resolved package versions/hashes.
  - [x] Manual Verification: Generate lockfile, inspect for correctness and reproducibility.

- [x] **Task 3.2: Lockfile update on install**
  - [x] Update `almd-lock.lua` after each install.
  - [ ] Manual Verification: Compare lockfile before/after install, confirm correct changes.

## Milestone 4: CLI Command Feature Parity

- [x] **Task 4.1: Implement `init` command**
  - [x] Create/initialize a new Almandine project.
  - [x] Manual Verification: Run `almd init`, check that manifest is created.

- [x] **Task 4.2: Implement `add`/`i` command**
  - [x] Add dependencies to `project.lua` and download them.
  - [x] Manual Verification: Add a dependency, verify it appears and is downloaded.
  - [x] Automated Test: Add, download, and verify real dependencies (Task 4.2, 2025-04-27)

- [ ] **Task 4.2b: Make <dep_name> optional for `add` command (2025-04-28)**
  - [x] Allow `almd add <source>` (GitHub raw URL) with no explicit dependency name; infer name from filename in URL.
  - [x] If <dep_name> is omitted, use <FILENAME>.lua as the manifest key and output file.
  - [x] Continue to support explicit <dep_name> as override.
  - [x] Update help text and documentation for new usage.
  - [ ] Manual Verification: Add dependency by URL only, check manifest and file, verify correct behavior for both implicit and explicit names.

- [x] **Task 4.3: Implement `remove`/`rm`/`uninstall`/`un` command**
  - [x] Remove dependencies from `project.lua` and project files.
  - [x] Manual Verification: Remove a dependency, verify it is deleted.

- [x] **Task 4.4: Implement `update`/`up`/`upgrade` command (`--latest` flag)**
  - [x] Update dependencies to latest allowed version or to latest with `--latest`.
  - [x] Manual Verification: Run `almd update`, check versions/hashes.

- [x] **Task 4.5: Implement `run` command (allow omitting if no conflicts)**
  - [x] Run scripts from `project.lua`; allow omitting `run` if no conflict.
  - [x] Manual Verification: Run scripts with and without `run`, check output.

- [x] **Task 4.6: Implement `list` command**
  - [x] List installed dependencies and their versions.
  - [x] Manual Verification: Run `almd list`, verify output.

- [ ] **Task 4.7: Improve test coverage for src/utils/manifest.lua (2025-04-28)**
  - [ ] Add comprehensive tests for all code paths in manifest.safe_load_project_manifest (valid, file-not-found, syntax error, runtime error, non-table return).
  - [ ] Manual Verification: Run all tests, confirm all branches are covered in luacov.stats.

- [ ] **Update all usage/help text to refer to the CLI tool as `almd` (not `almandine`).**

## Milestone 5: Installer and Wrapper Scripts

- [x] **Task 5.1: Cross-platform installer and advanced wrapper scripts for `almd` CLI**
  - [x] Create installer scripts (`install.sh`, `install.ps1`) to copy project files and wrapper scripts to user-specific locations on Linux/macOS and Windows.
  - [x] Implement robust wrapper scripts (`install/almd.sh`, `install/almd.bat`) that:
    - Locate a suitable Lua interpreter (`lua`, `lua5.4`, ..., `luajit`) automatically.
    - Always run the CLI from the script's directory for portability (not assuming install location).
    - Set `LUA_PATH` so that `src/lib` modules are found regardless of working directory (batch script only).
    - Forward all arguments to `src/main.lua`.
  - [ ] Manual Verification: Run installer on each platform, verify `almd` is available on the command line and launches the Lua app with arguments, even when run from any directory.

- [ ] **Task 5.2: Implement `self uninstall` command**
  - [ ] Add `almd self uninstall` to remove wrapper scripts and Lua CLI folder.
  - [ ] Manual Verification: Run `almd self uninstall`, confirm all relevant files are deleted. (2025-04-28)

- [ ] **Task 5.3: Remote installer fetches and installs from GitHub Releases** (2025-04-28)
  - [ ] Update `install.sh` and `install.ps1` so they fetch and extract the distributable CLI zip from the latest (or specified) release on GitHub, using robust multiplatform methods (`curl`, `wget`, etc.).
  - [ ] Manual Verification: Download and run installer scripts on all platforms with no other files present, confirm correct CLI installation and usability.

- [ ] **Task 5.4: Modularize and delegate CLI help output** (2025-04-28)
  - [ ] Refactor all CLI help/usage output so that each command module in `src/modules/` exposes a `help_info()` function returning or printing its usage/help text (using `almd` as the CLI name).
  - [ ] Update `src/main.lua` to route `--help`/`help` invocations to the relevant module, and print a summary help if called as `almd --help` or `almd help` with no subcommand.
  - [ ] Manual Verification: Run `almd --help`, `almd help <command>`, and `almd <command> --help` to verify correct output and routing.

## Milestone 6: Automated Release Workflow & Changelog

- [x] **Task 6.1: Automated Release Workflow & Changelog (2025-04-28)**
  - [x] Add a GitHub Action in `.github/workflows` to:
    - Build a distributable release zip containing the CLI and all required files (for use by `almd self update`).
    - Automatically generate a changelog listing all changes since the previous release (using commit messages or PR titles).
    - Attach the zip and changelog to a new GitHub Release.
    - Ensure the workflow is professional and cross-platform aware.
  - [ ] Manual Verification: Trigger release, verify zip contents, changelog accuracy, and release quality.

- [ ] **Task 6.2: Migrate all src/spec tests to Busted framework (2025-04-28)**
  - [ ] For each test file in `src/spec` named `*_test.lua`, create a corresponding `*_spec.lua` using the Busted test library and idioms (`describe`, `it`, `assert`).
  - [ ] Preserve all test logic, grouping, and documentation; follow project Lua and LDoc standards.
  - [ ] Do not delete or move original files unless explicitly approved.
  - [ ] Manual Verification: Run all new specs with Busted, confirm all tests pass and logic is preserved.

---

## Lessons Learned (2025-04-28)

- **Never overwrite or assign to read-only global fields (e.g., `os.execute`) in tests or implementation code.**
  - This practice is flagged by luacheck and can cause subtle bugs or incompatibilities across Lua versions and environments.
  - **Preferred approach:** Refactor code to allow dependency injection (e.g., pass an executor function as a parameter), so tests can inject mocks or stubs without touching global state.
  - If output capture is required in tests, prefer dependency injection or local overrides. Directly overriding global functions like `print` or redirecting `io.output` may not work reliably in all environments (especially with Busted or other test runners).
  - Always verify that any test workaround is both cross-platform and compliant with project linting and style rules.

---

## Active Work

- [ ] **Task 6.2: Migrate all src/spec tests to Busted framework (2025-04-28)**
  - [ ] For each test file in `src/spec` named `*_test.lua`, create a corresponding `*_spec.lua` using the Busted test library and idioms (`describe`, `it`, `assert`).
  - [ ] Preserve all test logic, grouping, and documentation; follow project Lua and LDoc standards.
  - [ ] Do not delete or move original files unless explicitly approved.
  - [ ] Manual Verification: Run all new specs with Busted, confirm all tests pass and logic is preserved.

## Backlog / Discovered Tasks

- (Add any new features, bugs, or improvements discovered during development)

---

## Milestone 7: CI/CD Improvements

- [ ] **Task 7.1: Add CI workflow for lint, test, and coverage (2025-04-28)**
  - [ ] Create a GitHub Actions workflow that runs on push and PR.
  - [ ] Test on Lua 5.1, 5.2, 5.3, 5.4, and LuaJIT.
  - [ ] Run `luacheck` on `src/` and `src/spec/`.
  - [ ] Run Busted tests with coverage using `luacov`.
  - [ ] Upload coverage to Coveralls (on Lua 5.1 only, using `COVERALLS_REPO_TOKEN`).
  - [ ] Manual Verification: Check workflow runs and reports status for all jobs; confirm coverage appears on Coveralls.

- [ ] **Task 7.2: Fix all luacheck warnings in src/ and src/spec (2025-04-29)**
  - [ ] Address all line length, unused variable, shadowing, and read-only global warnings reported by `luacheck`.
  - [ ] Ensure all changes conform to project Lua and LDoc standards.
  - [ ] Manual Verification: Run `luacheck` and confirm 0 warnings/errors.

- [ ] **Task 7.3: Add pre-commit hook to run luacheck on staged Lua files (2025-04-28)**
  - [ ] Create a portable pre-commit hook script in `install/pre-commit.sample`.
  - [ ] Script must block commit if any staged `.lua` files fail `luacheck`.
  - [ ] Manual Verification: Copy hook to `.git/hooks/pre-commit`, stage a `.lua` file with a lint error, and confirm commit is blocked.

- [ ] **Task 7.4: Add `.luacov` config to exclude `.luarocks/lua/` from coverage (2025-04-28)**
  - [ ] Create `.luacov` in the project root.
  - [ ] Exclude `.luarocks/lua/` from coverage to prevent skewed results.
  - [ ] Manual Verification: Confirm coverage report excludes `.luarocks/lua/` files.

- [ ] **Task 7.5: Add pre-commit hook to run Stylua on staged Lua files (2025-04-28)**
  - [ ] Create a portable pre-commit hook script in `install/pre-commit.sample`.
  - [ ] Script must block commit if any staged `.lua` files fail formatting check via `npx @johnnymorganz/stylua-bin src/`.
  - [ ] Manual Verification: Copy hook to `.git/hooks/pre-commit`, stage a `.lua` file with a formatting error, and confirm commit is blocked.

- [ ] **Task 7.3: Eliminate luacheck read-only global warnings in filesystem tests (2025-04-28)**
  - [ ] Refactor `filesystem.ensure_lib_dir` and its tests to avoid assigning to `os.execute` or `package.config`.
  - [ ] Use dependency injection or local overrides for path separator and command execution in tests.
  - [ ] Manual Verification: Run all specs and confirm no warnings about read-only global fields.

## Milestone 8: Refactor Downloader Utility

- [ ] **Task 8.1: Refactor downloader utility to remove external dependencies and use wget/curl (2025-04-28)**
  - [ ] Update `src/utils/downloader.lua` to eliminate LuaSocket/ltn12 and implement download logic using wget/curl via os.execute.
  - [ ] Manual Verification: Run `almd` and all commands that download files on Linux, macOS, and Windows; confirm correct behavior and no dependency errors.

*Last updated: 2025-04-29*
