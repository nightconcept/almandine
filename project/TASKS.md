# Task Checklist: Almandine `init` Command Refactor & Testing

**Purpose:** Tracks tasks, milestones, and backlog for refactoring the `init` command for better testability and implementing its associated E2E testing using the established infrastructure.

**Multiplatform Policy:** All tasks, implementations, and verifications MUST consider cross-platform compatibility (Linux, macOS, and Windows) unless otherwise specified.

---

## CLI Tool Name

- The CLI executable is called `almd`.
- All documentation, usage, and examples should refer to the CLI as `almd`.

---

## Milestone 1: `init` Command Refactoring

**Goal:** Refactor `src/modules/init.lua` to use dependency injection for improved testability, mirroring the structure of `src/modules/add.lua`.

- [x] **Task 1.1: Define `InitDeps` Structure**
    - [x] Define an `InitDeps` table structure using EmmyLua annotations in `src/modules/init.lua`.
    - [x] This structure should include functions for:
        - Prompting the user for input (`prompt`).
        - Printing output (`println`).
        - Saving the manifest file (`save_manifest`).
    - [x] Manual Verification: Code review confirms the `InitDeps` structure is well-defined and covers necessary dependencies.

- [x] **Task 1.2: Refactor `init_project` Function**
    - [x] Modify the `init_project` function in `src/modules/init.lua` to accept the `InitDeps` table as an argument.
    - [x] Update the internal logic to use the injected functions (e.g., `deps.prompt`, `deps.println`, `deps.save_manifest`) instead of direct `io` calls or `require`d utils where applicable.
    - [x] Consider breaking down the logic into smaller, internal helper functions if it improves clarity and testability.
    - [x] Ensure existing functionality (prompting for name, version, license, description, scripts, dependencies, writing `project.lua`) remains unchanged.
    - [x] Manual Verification: Code review confirms the refactoring uses dependency injection correctly and preserves the original interactive behavior logic.

- [x] **Task 1.3: Update `main.lua` for Dependency Injection**
    - [x] Modify `src/main.lua` where the `init` command is handled.
    - [x] Create an instance of the `InitDeps` table, providing the actual implementations (e.g., wrapping `io.read`/`io.write` for `prompt`, `print` for `println`, `manifest_utils.save_manifest` for `save_manifest`).
    - [x] Pass this `InitDeps` table when calling the refactored `init_project` function.
    - [x] Manual Verification: Run `almd init` manually. Verify the interactive prompts work as before and `project.lua` is created correctly. Check argument parsing logic in `main.lua`.

## Milestone 2: E2E Tests for `init` Command

**Goal:** Implement E2E test cases for the `init` command using Busted and the existing scaffolding helper, accounting for its interactive nature.

- [x] **Task 2.1: Create `init_spec.lua` Structure**
    - [x] Create `src/spec/e2e/modules/init_spec.lua` (if it doesn't exist or is empty).
    - [x] Set up the `describe` block.
    - [x] Implement `before_each` to call `scaffold.create_sandbox_project()`. Note: `init_project_file` is likely *not* needed here, as `init`'s purpose is to create it.
    - [x] Implement `after_each` to call the `cleanup_func()`.
    - [x] Manual Verification: Run the empty spec file with `busted`; ensure setup/teardown execute without errors in a clean sandbox.

- [ ] **Task 2.2: Develop Strategy for Testing Interaction**
    - [ ] Analyze how `scaffold.run_almd` (or direct `main.lua` calls) can handle the interactive prompts of `almd init`.
    - [ ] Options might include:
        - Modifying `scaffold.run_almd` to accept predefined input streams/responses.
        - Mocking the `prompt` function within the `InitDeps` table specifically during tests.
        - Running `init` non-interactively if an option for that is added later (outside current scope).
    - [ ] Decide on and document the chosen strategy. Implement any necessary helpers in `scaffold.lua` or test setup.
    - [ ] Manual Verification: Demonstrate the chosen interaction strategy works reliably in a sample test case.

- [ ] **Task 2.3: Implement E2E Test: Basic Initialization (Defaults)**
    - [ ] Implement an `it` block for running `almd init` and accepting default values for all prompts.
    - [ ] Use the chosen interaction strategy (Task 2.2) to provide input (e.g., just pressing Enter).
    - [ ] Use `scaffold.read_project_lua` and Busted `assert` functions to verify:
        - `project.lua` is created.
        - The content matches the expected structure with default values (e.g., name "my-lua-project", version "0.0.1", default "run" script).
    - [ ] Manual Verification: Run `busted src/spec/e2e/modules/init_spec.lua`; confirm this test passes.

- [ ] **Task 2.4: Implement E2E Test: Initialization with Custom Values**
    - [ ] Implement an `it` block for running `almd init` and providing custom values for prompts (name, version, description, license, scripts, dependencies).
    - [ ] Use the interaction strategy to provide specific custom input.
    - [ ] Verify `project.lua` is created with the exact custom values provided.
    - [ ] Manual Verification: Run `busted`; confirm test passes.

- [ ] **Task 2.5: Implement E2E Test: Initialization Over Existing `project.lua`**
    - [ ] Implement an `it` block where `scaffold.init_project_file` is used first to create a dummy `project.lua`.
    - [ ] Run `almd init` with custom values.
    - [ ] Verify the original `project.lua` is overwritten with the newly generated content based on the interactive session.
    - [ ] Manual Verification: Run `busted`; confirm test passes.

---

## Analysis & Next Steps

### Potential Improvements for `init` Functionality

1.  **Non-Interactive Mode:** Add a `--yes` or `-y` flag to skip prompts and use default values, or potentially allow providing values via flags (e.g., `almd init --name myproj --version 0.1`).
2.  **Template-Based Initialization:** Allow initialization based on predefined project templates.
3.  **Input Validation:** Add validation for inputs like version numbers (SemVer format) or checking for invalid characters in the project name.
4.  **Error Handling:** Improve error handling if `project.lua` cannot be written (e.g., permissions issues).

*This TASKS.md outlines the refactoring and initial E2E testing. Further tasks can be added for the potential improvements or more complex test scenarios.* 