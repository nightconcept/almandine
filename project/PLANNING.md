# Almandine Package Manager

## 1. Introduction

Almandine (`almd` as the CLI command) is a lightweight package manager for Lua projects. It enables simple, direct management of single-file dependencies (from GitHub or other supported repositories), project scripts, and project metadata. Almandine is designed for projects that want to pin specific versions or commits of files without managing complex dependency trees.

## 2. Core Features

- **Single-file Downloads:** Fetch individual Lua files from remote repositories (e.g., GitHub), pinning by semver (if available) or git commit hash.
- **No Dependency Tree Management:** Only downloads files explicitly listed in the project; does not resolve or manage full dependency trees.
- **Project Metadata:** Maintains project name, type, version, license, and package description in `project.lua`.
- **Script Runner:** Provides a central point for running project scripts (similar to npm scripts).
- **Lockfile:** Tracks exact versions or commit hashes of all downloaded files for reproducible builds.
- **License & Description:** Exposes license and package description fields in `project.lua` for clarity and compliance.
- **Cross-Platform:** Cross-platform compatible (Linux, macOS, and Windows).

## 3. Folder Structure

Sample minimal structure for an Almandine-managed project:

* `project.lua`          # Project manifest (metadata, scripts, dependencies)
* `almd-lock.lua`   # Lockfile (exact versions/hashes of dependencies)
* `scripts/`             # (Optional) Project scripts
* `lib/`                 # (Optional) Downloaded packages/files
* `src/`                 # (Optional) Project source code
  * `lib/`               # (Optional) Internal reusable modules (e.g., downloader, lockfile)
  * `modules/`           # All CLI command modules (init, add, remove, etc.)
* `install/`             # Cross-platform CLI wrapper scripts
  * `almd`               # Bash/sh wrapper for Linux/macOS (portable, finds Lua, runs from script dir)
  * `almd.ps1`           # Batch wrapper for Windows PowerShell (portable, finds Lua, runs from script dir, sets LUA_PATH)

## 4. File Descriptions

### `project.lua`

Project manifest. Example fields:

```lua
return {
  name = "my-lua-project",
  lua = ">=5.1",
  type = "library", -- or "application"
  version = "1.0.0",
  license = "MIT",
  description = "A sample Lua project using Almandine.",
  scripts = {
    test = "lua tests/run.lua",
    build = "lua build.lua"
  },
  dependencies = {
    ["lunajson"] = "~1.3.4", -- semver or commit hash
    ["somefile"] = "github:user/repo/path/file.lua@abcdef"
  }
}
```

- `name` (string): Project name.
- `lua` (string, optional): Minimum or specific Lua version required for the project. Accepts version constraints such as ">=5.1", "=5.1", ">5.1", or "<5.4".
- `type` (string): Project type, either "library" or "application".
- `version` (string): Project version.
- `license` (string): Project license.
- `description` (string): Project description.
- `scripts` (table): Project scripts.
- `dependencies` (table): Project dependencies.

### `almd-lock.lua`

Tracks resolved dependencies for reproducible installs. Example fields:

```lua
return {
  api_version = "1",
  package = {
    lunajson = { version = "1.3.4", hash = "sha256:..." },
    somefile = { source = "github:user/repo/path/file.lua", hash = "abcdef" }
  }
}
```

### `src/lib/`

Contains internal reusable Lua modules used by the Almandine package manager itself (e.g., downloader, lockfile). Not for user-downloaded dependencies.

### `src/modules/`

Contains all CLI command modules (such as init, add, remove, etc.) for the package manager. All new modules must be placed here. Do not place command modules elsewhere.

### `src/main.lua`

Main entrypoint for the CLI. Responsible for:

- Parsing CLI arguments and dispatching to the correct command module in `src/modules`.
- Explicitly handling all standard command aliases (e.g., install/in/ins, remove/rm/uninstall/un, update/up/upgrade, add/i, etc.).
- All usage/help output, documentation, and examples must use `almd` as the CLI tool name (never `almandine`).
- When adding or modifying commands or aliases, update `src/main.lua` to ensure all are handled, and update documentation/tasks accordingly.

### `install/`

Contains cross-platform wrapper scripts for launching the CLI application:

- `almd.sh`: POSIX shell script for Linux/macOS; finds a suitable Lua interpreter, runs from its own directory, dispatches all arguments to `src/main.lua`.
- `almd.bat`: Batch script for Windows CMD; finds a suitable Lua interpreter, runs from its own directory, sets `LUA_PATH` so `src/lib` modules are found, dispatches all arguments to `src/main.lua`.

## 5. Conclusion

Almandine aims to provide a simple, robust, and reproducible workflow for Lua projects that need lightweight dependency management and script automation, without the complexity of full dependency trees.

---

## Tech Stack

- Lua 5.1–5.4 / LuaJIT 2.1
- Platform: Cross-platform (Linux, macOS, Windows)

## Project Rules

### 0. Folder Structure Compliance (MANDATORY)

- **NO files or directories may be added, removed, or relocated** outside of the structure defined in PLANNING.md without explicit prior approval.
- **Any change to the folder structure requires:**
  1. Approval from project maintainers.
  2. Immediate update of PLANNING.md to reflect the change, BEFORE implementation.
- **All source code goes into the `src` directory**.

This rule is absolute and takes precedence over all other guidelines.

### 1. Mandatory Pre-computation & Context Assimilation

- **ACTION REQUIRED (Start of Session):** Read and internalize the contents of `PLANNING.md`. This document contains critical information about the project's architecture, goals, overall style guide, and constraints.
- **ACTION REQUIRED (Before Each Task):**
    1. Consult `TASK.md` to understand the current assignment.
    2. If the specific task you are about to work on is not listed, **add it** to `TASK.md` with a concise description and the current date (`YYYY-MM-DD`).
    3. **Develop an Implementation Plan:** Before writing or suggesting code, outline:
        - A brief description of the problem being solved.
        - A high-level overview of your proposed solution.
        - A list of specific steps required for implementation.
    4. **Analyze Existing Code:** Review relevant existing code files to understand the current implementation, context, and structure *before* suggesting modifications or additions. Read and internalize the contents of `digest.txt`. This document contains a digest of the current state of the project only up to the latest commit.

---

### 2. Code Implementation Standards

#### Lua Coding Standards (LDoc Compatible)

##### 2.1. Language & Environment

- **Primary Language:** Lua (specifically targeting Lua 5.1).
- **Compatibility:** All code must be compatible with versions 5.1 through 5.4 and LuaJIT.

##### 2.2. Modularity & Structure

- **File Length Limit:** No single Lua file (`.lua`) should exceed 500 lines of code. Refactor larger files into smaller, focused modules or helper files.
- **Organization:** Structure code into clearly separated modules, logically grouped by feature or responsibility. Follow the existing file structure patterns outlined in `PLANNING.md`.
- **Imports:** Use clear and consistent import paths. Prefer relative imports for modules within the same logical package/feature area. Confirm module paths exist before using them.
- **Dependencies:** Use no external dependencies.

##### 2.3. Style & Formatting (Lua)

- **Base Style:** Adhere to the Lua Standard Style guidelines.
- **Type Hinting:** Use LDoc-style type annotations within documentation comments (`@type`, `@param name [type]`, `@return [type]`, `@class`, `@field`) where appropriate to clarify data structures and function signatures.
- **Indentation:** Use 2 spaces for indentation (strictly enforce).
- **Strings:** Prefer double quotes (`"`) for string literals.
- **Line Length:** Maximum line length is 120 characters.
- **Function Calls:** Always use parentheses `()` for function calls, even if no arguments are passed.
- **Spacing:** Do *not* add a space between a function name and its opening parenthesis (e.g., `my_function()` not `my_function ()`).
- **Statements:** Do not collapse simple statements onto a single line if they would normally be separate.
- **Variables:** Use `local` variables by default to avoid polluting the global namespace.
  - Variable names with larger scope should be more descriptive than those with smaller scope. One-letter variable names should be avoided except for very small scopes (less than ten lines) or for iterators.
  - `i` should be used only as a counter variable in for loops (either numeric `for` or `ipairs`).
  - Prefer more descriptive names than `k` and `v` when iterating with `pairs`, unless you are writing a function that operates on generic tables.
  - Use `_` for ignored variables (e.g. in for loops):

    ```lua
      for _, item in ipairs(items) do
         do_something_with_item(item)
      end
      ```

      ```lua
      for _, name in pairs(names) do
         -- ...stuff...
      end
      ```

  - Variables and function names should use `snake_case`.
  - Classes should use `CamelCase`. Acronyms (e.g. XML) should only uppercase the first letter (`XmlDocument`).
  - Class methods should use `snake_case` too.
  - Prefer using `is_` when naming boolean functions:

      ```lua
      -- bad
      local function evil(alignment)
         return alignment < 100
      end

      -- good
      local function is_evil(alignment)
         return alignment < 100
      end
      ```

  - `UPPER_CASE` shall be used with "constants" only (variables intended not to be reassigned after initial definition).
- **File Header:** Files should have a header and description using a block comment.

  ```lua
  --[[
    File Purpose/Module Summary

    A more detailed description of what the file/module does, its responsibilities,
    and perhaps how it fits into the larger system.
  ]]--
  ```

- **DO NOT** include Lua/LuaJIT version compatibility info in the top file comment; this is covered by the overall project standard (Section 2.1).

##### 2.4. Documentation & Comments (LDoc)

- **Docstrings:** Every public function, class, and module should have a documentation comment using the LDoc format (starting with `---`). Include descriptions for the element's purpose, parameters (`@param`), and return values (`@return`). Markdown within descriptions is permitted.
- **Module Documentation:** Use a `---` comment block at the top of the file (after the file header block comment) to document the module itself, potentially using `@module ModuleName`.
- **Example Format:**

  ```lua
  --[[
    math_utils

    Provides utility functions for basic mathematical operations.
  ]]--

  --- Mathematical utilities module.
  -- Provides simple arithmetic functions as examples.
  -- @module math_utils

  local M = {}

  --- Adds two numbers together.
  -- Can include **markdown** for *emphasis*.
  -- @param num1 number The first number to add.
  -- @param num2 number The second number to add.
  -- @return number The sum of num1 and num2.
  -- @usage local math = require('math_utils'); local sum = math.add(5, 3) -- sum is 8
  function M.add(num1, num2)
    -- Function implementation
    local result = num1 + num2 -- Example logic
    return result
  end

  --- Represents a point in 2D space.
  -- @type Point {x: number, y: number}
  local point_example -- just declaring a variable that uses the type

  --- A simple class example.
  -- @class SimpleClass
  -- @field name string The name associated with this instance. Default is "Default".
  SimpleClass = {}
  SimpleClass.__index = SimpleClass

  --- Creates a new instance of SimpleClass.
  -- @param initial_name [string] The initial name (optional).
  -- @return SimpleClass A new instance of SimpleClass.
  function SimpleClass:new(initial_name)
    local self = setmetatable({}, SimpleClass)
    self.name = initial_name or "Default"
    return self
  end

  --- Gets the name of the instance.
  -- @return string The current name.
  function SimpleClass:get_name()
      return self.name
  end

  return M
  ```

- **Code Comments:** Add comments to explain non-obvious logic, complex algorithms, or important decisions. Focus on the *why*, not just the *what*.
- **Reasoning Comments:** For complex or potentially confusing blocks of code, add an inline comment starting with `# Reason:` explaining the rationale behind the implementation choice.
- **README Updates:** Update `README.md` if changes involve:
  - Adding new core features.
  - Changing dependencies.
  - Modifying setup or build steps.

---

### 3. Development Workflow & Modification Rules

- **Implementation Plan:** Always create the plan outlined in Section 1 before coding.
- **Read First:** Always read and understand existing code before modifying or adding to it.
- **Focus:** Keep changes focused on the specific task. Do not refactor unrelated code unless it's part of the explicit task.
- **Small Functions:** Prefer small, single-purpose functions.
- **Code Modification Principles:**
  - Aim for clean, elegant, and idiomatic Lua/LÖVE solutions.
  - Explain the *rationale* behind significant suggestions or changes.
  - Propose minimal, incremental changes that are easy to review.
  - Prioritize low-risk refactoring.
  - Avoid code duplication; promote reusability.
  - Leverage Lua's strengths (tables, first-class functions).
  - Be aware of common Lua pitfalls (e.g., table indexing, scope, closures).
- **Dependencies:** Do not introduce new external dependencies unless absolutely necessary and explicitly discussed/approved.
- **Commits:** Ensure commit messages follow the Conventional Commits specification (`https://www.conventionalcommits.org/en/v1.0.0/`). (AI will likely provide code/suggestions, user performs the commit).
- **Manual Testing:** When developing a task for TASK.md, always allow user to manually test the changes and provide instructions.

---

### 4. Specifying and Verifying Behavior

- **Specify Behavior for New/Modified Components:** Any new feature (function, class, significant logic) or modification to existing logic requires corresponding specifications that describe its expected behavior. This ensures clarity and verifies *what* it's supposed to do from an external viewpoint.

- **Specification Location:** Behavior specifications must reside in a top-level `/spec` directory. This directory's structure should mirror the source code being specified, making it easy to locate relevant specifications.
  - *Example:* Specifications for `game/engine/my_module.lua` belong in `spec/engine/my_module_spec.lua`.

- **Describe Key Behavioral Scenarios:** Each component's specification should describe its behavior under various conditions using `describe` and `it` blocks. At minimum, include scenarios covering:
  - **Expected Behavior:** At least one example (`it` block) describing the typical, successful interaction or outcome (the "happy path").
    - *Example:* `it("should return the correct sum for two positive numbers")`
  - **Boundary Conditions:** At least one example exploring behavior at known or likely limits or edge cases.
    - *Example:* `it("should handle empty input lists gracefully")`
    - *Example:* `it("should clamp position at the maximum screen boundary")`
  - **Handling Undesired Situations:** At least one example describing how the component behaves when encountering errors, invalid inputs, or exceptional conditions.
    - *Example:* `it("should return nil when a required parameter is missing")`
    - *Example:* `it("should error if division by zero is attempted")`

- **Maintain Living Documentation:** Software evolves, and so must its specifications. When modifying existing logic, **review and update the corresponding specifications** to ensure they accurately reflect the component's *current* behavior. Outdated specifications are misleading.

- **AI Collaboration in Specification:** When assisting with behavior specification:
  - **DO** generate executable specification code using `busted` in `_spec.lua` files (aligning with Busted's convention).
  - **DO** clearly summarize suggested specifications by describing the *behavior* being specified and its context. Frame suggestions around *what* should happen under certain conditions, suitable for `describe` or `it` blocks.
  - *Example:* "Specify behavior when `my_function` receives `nil` input."
  - *Example:* "Specify player collision behavior at the screen edge."
  - *Example:* "Describe the outcome when saving data with an invalid format."
  - Use the `busted` library for all specifications.
  - Within specification files (`_spec.lua`), use full module paths for `require` statements (e.g., `require("game.engine.core.scene")`).

---

### 5. AI Interaction Protocols

- **Clarity:** Never assume missing context or requirements. If uncertain about the task, project state, or constraints, **ask clarifying questions** before proceeding.
- **Factuality:** Do not "hallucinate" or invent libraries, functions, APIs, or file paths. Only use verified LÖVE APIs, standard Lua functions, and modules confirmed to exist within the project.
- **Verification:** Always confirm file paths and module names exist (based on provided context or previous interactions) before referencing them in code examples, tests, or explanations.
- **Code Modification Safety:** Never delete or overwrite existing code unless:
  - Explicitly instructed to do so by the user.
  - It is a defined part of the current task listed in `TASK.md`.
- **Model Capability Awareness:** If you assess that a task is complex and might benefit significantly from a more advanced model's capabilities, state this clearly **at the beginning of your response** using **bold text**. Example: "**Suggestion: This refactoring task is complex and involves deep analysis of interactions. A more advanced model might provide a more robust solution.**"
- **Collaboration Style:** Respond in a friendly, helpful, and collaborative tone, as if we are teammates working together.
- **Task Completion:** Upon completing the implementation/suggestion for a task, explicitly state that the task requirements (as understood) have been met. Remind the user to mark the task as complete in `TASK.md`.
