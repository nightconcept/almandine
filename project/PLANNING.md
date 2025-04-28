# Almandine Package Manager

## 1. Introduction

Almandine is a lightweight package manager for Lua projects. It enables simple, direct management of single-file dependencies (from GitHub or other supported repositories), project scripts, and project metadata. Almandine is designed for projects that want to pin specific versions or commits of files without managing complex dependency trees.

## 2. Core Features

- **Single-file Downloads:** Fetch individual Lua files from remote repositories (e.g., GitHub), pinning by semver (if available) or git commit hash.
- **No Dependency Tree Management:** Only downloads files explicitly listed in the project; does not resolve or manage full dependency trees.
- **Project Metadata:** Maintains project name, type, version, license, and package description in `project.lua`.
- **Script Runner:** Provides a central point for running project scripts (similar to npm scripts).
- **Lockfile:** Tracks exact versions or commit hashes of all downloaded files for reproducible builds.
- **License & Description:** Exposes license and package description fields in `project.lua` for clarity and compliance.

## 3. Folder Structure

Sample minimal structure for an Almandine-managed project:

* `project.lua`          # Project manifest (metadata, scripts, dependencies)
* `almd-lock.lua`   # Lockfile (exact versions/hashes of dependencies)
* `scripts/`             # (Optional) Project scripts
* `lib/`                 # (Optional) Downloaded packages/files
* `src/`                 # (Optional) Project source code
  * `lib/`               # (Optional) Internal reusable modules (e.g., downloader, lockfile)
  * `modules/`           # All CLI command modules (init, add, remove, etc.)

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
- When adding or modifying commands or aliases, update `src/main.lua` to ensure all are handled, and update documentation/tasks accordingly.

## 5. Conclusion

Almandine aims to provide a simple, robust, and reproducible workflow for Lua projects that need lightweight dependency management and script automation, without the complexity of full dependency trees.

---

## Tech Stack

* Lua 5.1–5.4 / LuaJIT 2.1
