# Snowdrop Package Manager – Task Checklist (TASK.md)

**Purpose:** Tracks all tasks, milestones, and backlog for the Snowdrop Lua package manager. Each task includes a manual verification step for running and inspecting all tests and code.

---

## Milestone 1: Project Manifest & Initialization

- [x] **Task 1.1: Design and implement `project.lua` manifest schema**
  - [x] Define fields: `name`, `type`, `version`, `license`, `description`, `scripts`, `dependencies`.
  - [x] Manual Verification: Review schema, create sample file, and validate with test loader.

- [x] **Task 1.2: CLI command to initialize a new Snowdrop project**
  - [x] Implement `snowdrop init` (creates `project.lua` with prompts).
  - [x] Create a portable shell wrapper script that finds a suitable Lua interpreter and runs `src/main.lua` with all arguments (works on macOS and Linux).
  - [x] Manual Verification: Run shell script with arguments, confirm it finds Lua and dispatches to CLI.
  - [x] Manual Verification: Run CLI, inspect output, ensure correct manifest generation.

## Milestone 2: Dependency Download & Pinning

- [ ] **Task 2.1: Implement file downloader (GitHub/raw URL support)**
  - [ ] Support pinning by semver or commit hash.
  - [ ] Manual Verification: Download a file, verify correct version/hash is retrieved.

- [ ] **Task 2.2: Implement dependency install command**
  - [ ] Parse `dependencies` from `project.lua`.
  - [ ] Download to correct location (e.g., `lib/`).
  - [ ] Manual Verification: Inspect downloaded files, check hashes/versions.

## Milestone 3: Lockfile Management

- [ ] **Task 3.1: Design and implement `snowdrop-lock.lua` schema**
  - [ ] Track `api_version`, resolved package versions/hashes.
  - [ ] Manual Verification: Generate lockfile, inspect for correctness and reproducibility.

- [ ] **Task 3.2: Lockfile update on install**
  - [ ] Update `snowdrop-lock.lua` after each install.
  - [ ] Manual Verification: Compare lockfile before/after install, confirm correct changes.

## Milestone 4: Script Runner

- [ ] **Task 4.1: Implement script runner (like npm scripts)**
  - [ ] Parse `scripts` from `project.lua`.
  - [ ] Allow running scripts via CLI (e.g., `snowdrop run test`).
  - [ ] Manual Verification: Run scripts, verify correct execution and output.

## Milestone 5: Project Metadata Display

- [ ] **Task 5.1: Implement CLI command to show project/package info**
  - [ ] Display name, description, license, version from `project.lua`.
  - [ ] Manual Verification: Run info command, check output matches manifest.

## Milestone 6: End-to-End Testing & Documentation

- [ ] **Task 6.1: Write and run end-to-end tests for all major workflows**
  - [ ] Test project init, install, lockfile, script running, info display.
  - [ ] Manual Verification: Run all tests, inspect results, and check code for style/compliance.

- [ ] **Task 6.2: Write user and developer documentation**
  - [ ] Document all commands, config fields, and workflows.
  - [ ] Manual Verification: Review docs for completeness and clarity.

---

## Active Work

- (List any tasks currently in progress here)

## Backlog / Discovered Tasks

- (Add any new features, bugs, or improvements discovered during development)

---

*Last updated: 2025-04-26*
