# Almandine – Lua Package Manager 💎

![License](https://img.shields.io/github/license/nightconcept/almandine)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/nightconcept/almandine/ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/nightconcept/almandine/badge.svg)](https://coveralls.io/github/nightconcept/almandine)
![GitHub last commit](https://img.shields.io/github/last-commit/nightconcept/almandine)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/nightconcept/almandine/badge)](https://scorecard.dev/viewer/?uri=github.com/nightconcept/almandine)

A modern, cross-platform, developer-friendly package manager for Lua projects.
Easily manage, install, and update Lua single-file dependencies with a single CLI: `almd`.

---

## ✨ Features

- 📦 **Easy Dependency Management**: Add, remove, and update Lua single-file dependencies with simple commands.
- 🔒 **Reproducible Installs**: Lockfiles ensure consistent environments across machines.
- 🏗️ **Project Initialization**: Scaffold new Lua projects with best practices.
- 🛠️ **Cross-Platform**: Works on Linux, macOS, and Windows.

---

## Requirements

### macOS/Linux
- [Nix](https://nixos.org/)
- [devenv](https://devenv.sh/)

### Windows
- Go 1.23+
- [pre-commit](https://pre-commit.com/)
- [xc](https://github.com/joerdav/xc) task runner

_Note: These can all be installed via Scoop._

---

## 🛠️ Usage

```sh
almd init                # Create a new Lua project
almd add <package>       # Add a dependency
almd remove <package>    # Remove a dependency
almd update              # Update dependencies
almd list                # List installed dependencies
```

---

## Tasks

### lint

Run linters.

```sh
golangci-lint run
```

### build

Builds the `almd` binary.

```sh
go build -o build/almd ./cmd/almd
go build -o build/almd.exe ./cmd/almd
```

### test

Run tests.

```sh
go test ./...
```


### ready

Prepare for commit.

```sh
gitingest -o project/digest.txt -e *.toml,*.txt,.roo/*,.cursor/*,build/ .
gofmt -l -w .
go vet ./...
go mod tidy -v
golangci-lint run --fix
```

### yolo

Yolo install the `almd` binary to Windows.

```sh
go build -o build/almd ./cmd/almd
go build -o build/almd.exe ./cmd/almd
pwsh.exe -ExecutionPolicy Bypass -File ./install.ps1 --local
```

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
