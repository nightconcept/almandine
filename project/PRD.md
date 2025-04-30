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

- `project.lua`          # Project manifest (metadata, scripts, dependencies)
- `almd-lock.lua`   # Lockfile (exact versions/hashes of dependencies)
- `scripts/`             # (Optional) Project scripts
- `lib/`                 # (Optional) Downloaded packages/files
- `src/`                 # (Optional) Project source code
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

## Project-Specific Coding Rules

These rules supplement the mandatory Global AI Project Guidelines. They define standards and practices unique to this specific project.

### 1. Language, Environment & Dependencies

* **Target Language:** Lua 5.1.
* **Compatibility:** All code must be compatible with Lua versions 5.1 through 5.4 and LuaJIT.
* **Dependencies:** **Strictly NO external dependencies** are permitted beyond standard Lua/LÖVE libraries specified in `PLANNING.md`.

### 2. Lua Coding Standards

These standards refine the general coding standards for Lua development within this project.

#### 2.1. Style & Formatting

- **Base Style:** Adhere primarily to the [Lua Standard Style](https://github.com/Olivine-Labs/lua-style-guide/blob/master/lua-style.md) guidelines, unless overridden below or in `PLANNING.md`.
- **Strings:** Prefer double quotes (`"`) for string literals.
- **Line Length:** Maximum line length is 120 characters.
- **Function Calls:** Always use parentheses `()` for function calls, even if no arguments are passed (e.g., `my_function()` not `my_function`).
- **Naming Conventions:**
  - Variables and function/method names use `snake_case`.
  - Classes use `CamelCase`. Acronyms within class names only uppercase the first letter (e.g., `XmlDocument`).
  - Prefer more descriptive names than `k` and `v` when iterating with `pairs`, unless writing a generic table function.
- **Type Hinting:** Use **LuaLS/EmmyLua style annotations** (`---@tag`) for type hinting to provide rich information for language servers and static analysis. Use overlapping tags like `---@param name type` and `---@return type` which are compatible with both LuaLS and LDoc where possible.

### 2.2. Documentation & Comments (LuaLS/EmmyLua Focus)

- **Docstrings:** Every public function, class, module-level table, field, and type alias requires documentation comments using **LuaLS/EmmyLua format** (starting with `---@tag`).
- **Common Tags:** Include descriptions and utilize common tags such as:
  - `---@class Name [Parent]` for classes.
  - `---@field name type [description]` for class or table fields.
  - `---@param name type [description]` for function parameters.
  - `---@return type [description]` for function return values.
  - `---@type TypeName [description]` for complex table shapes or custom types.
  - `---@alias Name Type` for defining type aliases.
  - `---@see OtherSymbol` for references.
  - `---@usage <example code>` for usage examples.
- **Clarity:** Ensure descriptions clearly explain the purpose and behavior. Markdown within descriptions is permitted.
- **Module Documentation:** Document modules by annotating the returned table or the main functions/classes within them using the standard tags. Avoid LDoc-specific `@module` tags.
- **LuaLS/EmmyLua Example Format:**

    ```lua
    --[[
      math_utils

      Provides utility functions for basic mathematical operations.
      Intended for use with LuaLS/EmmyLua tooling.
    ]]--

    --- Module containing mathematical utilities.
    local M = {}

    --- Represents a point in 2D space.
    --- @alias Point { x: number, y: number }

    --- Adds two numbers together.
    -- Can include **markdown** for *emphasis*.
    --- @param num1 number The first number to add.
    --- @param num2 number The second number to add.
    --- @return number The sum of num1 and num2.
    --- @usage local math = require('math_utils'); local sum = math.add(5, 3) -- sum is 8
    function M.add(num1, num2)
      -- LuaLS knows num1 and num2 are numbers
      local result = num1 + num2
      return result
    end

    --- A simple class example using metatables, documented for LuaLS.
    --- @class SimpleClass
    --- @field name string The name associated with this instance. Default is "Default".
    local SimpleClass = {}
    SimpleClass.__index = SimpleClass

    --- Creates a new instance of SimpleClass.
    --- @param initial_name string? The initial name (optional).
    --- @return SimpleClass A new instance.
    function SimpleClass:new(initial_name)
      local self = setmetatable({}, SimpleClass)
      self.name = initial_name or "Default" -- LuaLS knows self.name is a string field
      return self
    end

    --- Gets the name of the instance.
    --- @return string # The current name.
    function SimpleClass:get_name()
        return self.name
    end

    -- Make the class available if needed by other modules
    M.SimpleClass = SimpleClass

    return M
    ```

### 2.3. Implementation Notes

- Leverage Lua's strengths (e.g., tables for structures, first-class functions).
- Be aware of common Lua pitfalls (e.g., 1-based indexing vs. 0-based, global variable scope issues, closure behavior).

## 3. Testing & Behavior Specification (Busted)

These rules specify how testing and behavior specification, required by the global guidelines, are implemented in this project using the `busted` framework.

- **Specification Location:** Behavior specifications must reside in the top-level `/spec` directory. This directory's structure must mirror the `/src` directory being specified.
  - *Example:* Specifications for `src/game/engine/my_module.lua` belong in `spec/game/engine/my_module_spec.lua`.
- **File Naming:** Specification files must end with `_spec.lua`.
- **Framework:** Use the `busted` testing framework for all specifications.
- **Test Doubles:** **Actively use test doubles** like spies, stubs, and mocks (e.g., via `require('luassert.spy')` or similar assertion library utilities) to isolate units under test, control dependencies, and verify interactions effectively.
- **Scenario Coverage:** Each component's specification should describe its behavior under various conditions using `describe` and `it` blocks. Include scenarios covering, at minimum:
  - **Expected Behavior:** Typical, successful interactions (the "happy path").
  - **Boundary Conditions:** Behavior at known limits or edge cases.
  - **Undesired Situations:** Behavior with errors, invalid inputs, or exceptional conditions.
- **Require Paths:** Within specification files (`_spec.lua`), use full, project-relative module paths for `require` statements (e.g., `require("src.game.engine.core.scene")`). Do not use local relative paths.
