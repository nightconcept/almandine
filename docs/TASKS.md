# Task Checklist

## Milestone 1:EXAMPLE, DELETE ME

**Goal:** Create the basic Go project structure and the main CLI entry point using `urfave/cli`.

-   [x] **Task 1.1: Initialize Go Module**
    -   [x] Run `go mod init <module_path>` (e.g., `go mod init github.com/your-user/almandine`). *User needs to determine the module path.*
    -   [x] Add `urfave/cli/v2` dependency (`go get github.com/urfave/cli/v2`).
    -   [x] Manual Verification: `go.mod` and `go.sum` are created/updated.

-   [x] **Task 1.2: Create `main.go`**
    -   [x] Create the `main.go` file at the project root.
    -   [x] Add the basic `main` function.
    -   [x] Manual Verification: File exists.

-   [x] **Task 1.3: Basic `urfave/cli` App Setup**
    -   [x] Import `urfave/cli/v2`.
    -   [x] Create a new `cli.App` instance in `main`.
    -   [x] Set the `Name` (`almd`), `Usage`, and `Version` for the app.
    -   [x] Implement the `app.Run(os.Args)` call.
    -   [x] Manual Verification: Run `go run main.go --version` and confirm the version is printed. Run `go run main.go --help` and confirm basic usage is shown.

-   [x] **Task 1.4: Define CLI Binary Name Convention**
    -   [x] Ensure the target executable name built by Go is `almd`.
    -   [x] *Note:* A separate wrapper script/alias named `almd` will be used by end-users to call `almd`. This task is about the Go build output name. (Build command might be `go build -o almd .`)
    -   [x] Manual Verification: Build the project (`go build -o almd .`) and confirm the output file is named `almd`.
