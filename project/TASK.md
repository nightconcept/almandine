# Almandine Package Manager – Task Checklist (TASK.md)

**Purpose:** Tracks all tasks, milestones, and backlog for the Almandine Lua package manager. Each task includes a manual verification step for running and inspecting all tests and code.

---

## Milestone 1: Project Manifest & Initialization

- [x] **Task 1.1: Design and implement `project.lua` manifest schema**
  - [x] Define fields: `name`, `type`, `version`, `license`, `description`, `scripts`, `dependencies`.
  - [x] Manual Verification: Review schema, create sample file, and validate with test loader.

- [x] **Task 1.2: CLI command to initialize a new Almandine project**
  - [x] Implement `almandine init` (creates `project.lua` with prompts).
  - [x] Create a portable shell wrapper script that finds a suitable Lua interpreter and runs `src/main.lua` with all arguments (works on macOS and Linux).
  - [x] Manual Verification: Run shell script with arguments, confirm it finds Lua and dispatches to CLI.
  - [x] Manual Verification: Run CLI, inspect output, ensure correct manifest generation.

- [x] **Task 1.3: Create Windows CLI wrapper script (`almd.bat`)** 
  - [x] Implement a batch script at the project root that finds a suitable Lua interpreter and runs `src/main.lua` with all arguments (works on Windows).
  - [x] Manual Verification: Run batch script with arguments, confirm it finds Lua and dispatches to CLI.

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
  - [x] Manual Verification: Run `almandine init`, check that manifest is created.

- [x] **Task 4.2: Implement `add`/`i` command**
  - [x] Add dependencies to `project.lua` and download them.
  - [ ] Manual Verification: Add a dependency, verify it appears and is downloaded.

- [ ] **Task 4.3: Implement `remove`/`rm`/`uninstall`/`un` command**
  - [ ] Remove dependencies from `project.lua` and project files.
  - [ ] Manual Verification: Remove a dependency, verify it is deleted.

- [ ] **Task 4.4: Implement `update`/`up`/`upgrade` command (`--latest` flag)**
  - [ ] Update dependencies to latest allowed version or to latest with `--latest`.
  - [ ] Manual Verification: Run update, check versions/hashes.

- [ ] **Task 4.5: Implement `run` command (allow omitting if no conflicts)**
  - [ ] Run scripts from `project.lua`; allow omitting `run` if no conflict.
  - [ ] Manual Verification: Run scripts with and without `run`, check output.

- [ ] **Task 4.6: Implement `list` command**
  - [ ] List installed dependencies and their versions.
  - [ ] Manual Verification: Run `list`, verify output.

---

## Active Work

## Backlog / Discovered Tasks

- (Add any new features, bugs, or improvements discovered during development)

---

*Last updated: 2025-04-27*
