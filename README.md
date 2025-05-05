# Almandine – Lua Package Manager 💎

![License](https://img.shields.io/github/license/nightconcept/almandine)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/nightconcept/almandine/ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/nightconcept/almandine/badge.svg)](https://coveralls.io/github/nightconcept/almandine)
![GitHub last commit](https://img.shields.io/github/last-commit/nightconcept/almandine)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/nightconcept/almandine/badge)](https://scorecard.dev/viewer/?uri=github.com/nightconcept/almandine)

A modern, cross-platform, developer-friendly package manager for Lua projects.
Easily manage, install, and update Lua dependencies with a single CLI: `almd`.

---

## ✨ Features

- 📦 **Easy Dependency Management**: Add, remove, and update Lua dependencies with simple commands.
- 🔒 **Reproducible Installs**: Lockfiles ensure consistent environments across machines.
- 🏗️ **Project Initialization**: Scaffold new Lua projects with best practices.
- 🛠️ **Cross-Platform**: Works on Linux, macOS, and Windows.
- 🧑‍💻 **Self-Updating**: Seamless updates via GitHub Releases.
- 📝 **Automated Changelog**: Professional release workflow with changelog generation.

---

## 🚀 Quickstart

### Install via Shell (Linux/macOS)

```sh
curl -fsSL https://github.com/nightconcept/almandine/raw/main/install.sh | sh
```

### Install via PowerShell (Windows)

```powershell
irm https://github.com/nightconcept/almandine/raw/main/install.ps1 | iex
```

---

## 🛠️ Usage

```sh
almd init                # Create a new Lua project
almd add <package>       # Add a dependency
almd remove <package>    # Remove a dependency
almd update              # Update dependencies
almd list                # List installed dependencies
almd run <script>        # Run a script from project.lua
```

- See `almd --help` for all commands and options.

---

## 🤝 Contributing

We 💙 contributions! Please:

- Read [`project/PRD.md`](project/PRD.md) for architecture & folder rules.
- Follow the coding standards (see comments in source).
- All source code must go in `src/`.
- Open issues or pull requests for feedback and improvements.

---

## 📜 License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
