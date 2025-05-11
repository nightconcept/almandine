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
- [xc](https://github.com/joerdav/xc) task runner

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

### build

Builds the `almd` binary.

```sh
go build -o build/almd ./cmd/almd
go build -o build/almd.exe ./cmd/almd
```

### lint

Run lint.

```sh
golangci-lint run
```

### test

Run tests.

```sh
go test ./...
```

### ready

Prepare for commit.

```sh
go test ./...
go fmt ./...
go vet ./...
go mod tidy -v
golangci-lint run --fix
gitingest -o project/digest.txt -e *.toml,*.txt,.roo/*,.cursor/*,build/*,.devenv/*,.direnv/*,project/digest.txt .
```

### yolo

Build and install the `almd` binary to Windows.

```sh
go build -o build/almd.exe ./cmd/almd
pwsh.exe -ExecutionPolicy Bypass -File ./install.ps1 --local
```

## License

This project is licensed under the MIT License. See [LICENSE](docs/LICENSE) for details.
