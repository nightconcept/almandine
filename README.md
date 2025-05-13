# Almandine – Lua Package Manager 💎

![License](https://img.shields.io/github/license/nightconcept/almandine)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/nightconcept/almandine/ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/nightconcept/almandine/badge.svg)](https://coveralls.io/github/nightconcept/almandine)
![GitHub last commit](https://img.shields.io/github/last-commit/nightconcept/almandine)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/nightconcept/almandine/badge)](https://scorecard.dev/viewer/?uri=github.com/nightconcept/almandine)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/10539/badge)](https://www.bestpractices.dev/projects/10539)

A modern, cross-platform, developer-friendly package manager for Lua projects.
Easily manage, install, and update Lua single-file dependencies..

## Features

- 📦 **Easy Dependency Management**: Add, remove, and update Lua single-file dependencies with simple commands.
- 🔒 **Reproducible Installs**: Lockfiles ensure consistent environments across machines.
- 🛠️ **Cross-Platform**: Works on Linux, macOS, and Windows.

## 🚀 Installation

You can install `almd` by running the following commands in your terminal. These scripts will download and run the appropriate installer for your system from the `main` branch of the official repository.

### macOS and Linux

```sh
curl -LsSf https://raw.githubusercontent.com/nightconcept/almandine/main/install.sh | sh
```

### Windows

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/nightconcept/almandine/main/install.ps1 | iex"
```
## Requirements

### macOS/Linux
- [Nix](https://nixos.org/)
- [devenv](https://devenv.sh/)

### Windows
- Go 1.24
- [pre-commit](https://pre-commit.com/)
- [go-task](https://taskfile.dev/) task runner

_Note: These can all be installed via Scoop._


## Usage

```sh
almd init                # Create a new Lua project
almd add <package>       # Add a dependency
almd remove <package>    # Remove a dependency
almd install             # Install dependencies
almd list                # List installed dependencies
almd self update         # Update almd
```

## Tasks

Project tasks are managed using [go-task](https://taskfile.dev/). You can list available tasks with `task --list`.

### build

Builds the `almd` binary for Linux and Windows.

```sh
task build
```

### lint

Run lint.

```sh
task lint
```

### test

Run tests.

```sh
task test
```

### ready

Prepare for commit (runs tests, formats, lints, etc.).

```sh
task ready
```

### sign

Sign releases with GPG key.

```sh
task sign
```

### yolo

Build and install the `almd` binary to Windows.

```sh
task yolo
```

## License

This project is licensed under the MIT License. See [LICENSE](docs/LICENSE) for details.
