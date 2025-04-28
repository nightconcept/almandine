# Almandine Package Manager – Task Checklist (TASK.md)

**Purpose:** Tracks all tasks, milestones, and backlog for the Almandine Lua package manager. Each task includes a manual verification step for running and inspecting all tests and code.

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

---

## Active Work

## Backlog / Discovered Tasks

- (Add any new features, bugs, or improvements discovered during development)

---

*Last updated: 2025-04-28*
