package list

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/nightconcept/almandine/internal/core/config"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/urfave/cli/v2"
)

// setupListTestEnvironment creates an isolated test environment with configurable project files.
// The environment includes project.toml, almd-lock.toml, and any additional dependency files.
// Returns the path to the temporary directory.
func setupListTestEnvironment(t *testing.T, projectTomlContent string, lockfileContent string, depFiles map[string]string) string {
	t.Helper()
	tempDir := t.TempDir()

	if projectTomlContent != "" {
		projectTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
		err := os.WriteFile(projectTomlPath, []byte(projectTomlContent), 0644)
		require.NoError(t, err, "Failed to write project.toml")
	}

	if lockfileContent != "" {
		lockfilePath := filepath.Join(tempDir, config.LockfileName)
		err := os.WriteFile(lockfilePath, []byte(lockfileContent), 0644)
		require.NoError(t, err, "Failed to write almd-lock.toml")
	}

	for relPath, content := range depFiles {
		absPath := filepath.Join(tempDir, relPath)
		err := os.MkdirAll(filepath.Dir(absPath), 0755)
		require.NoError(t, err, "Failed to create parent directory for dep file")
		err = os.WriteFile(absPath, []byte(content), 0644)
		require.NoError(t, err, "Failed to write dependency file")
	}

	return tempDir
}

// runListCommand executes the list command in a test environment with captured output.
// Important: This function temporarily changes CWD and redirects stdout, but restores both
// even if the command fails. This allows for testing error cases without side effects.
func runListCommand(t *testing.T, testDir string, appArgs ...string) (string, error) {
	t.Helper()

	// Save original stdout and working directory for restoration
	originalStdout := os.Stdout
	originalWD, err := os.Getwd()
	require.NoError(t, err, "Failed to get current working directory")

	// Setup stdout capture
	r, w, _ := os.Pipe()
	os.Stdout = w

	err = os.Chdir(testDir)
	require.NoError(t, err, "Failed to change working directory to testDir")

	defer func() {
		os.Stdout = originalStdout
		err := os.Chdir(originalWD)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error changing back to original directory: %v\n", err)
		}
		_ = r.Close()
		_ = w.Close()
	}()

	app := &cli.App{
		Commands: []*cli.Command{
			ListCmd(),
		},
		// ExitErrHandler prevents os.Exit during tests while still capturing errors
		ExitErrHandler: func(context *cli.Context, err error) {
			if err != nil {
				fmt.Fprintf(os.Stderr, "Note: cli.ExitErrHandler caught error (expected for tests): %v\n", err)
			}
		},
	}
	fullArgs := []string{"almd"}
	fullArgs = append(fullArgs, appArgs...)

	t.Setenv("NO_COLOR", "1")

	cmdErr := app.Run(fullArgs)

	err = w.Close()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Note: Error closing pipe writer (often expected on app error): %v\n", err)
	}

	var outBuf bytes.Buffer
	_, readErr := outBuf.ReadFrom(r)
	if readErr != nil && readErr.Error() != "io: read/write on closed pipe" {
		require.NoError(t, readErr, "Failed to read from stdout pipe")
	}

	return outBuf.String(), cmdErr
}

// Tests for various states of project.toml without dependencies
func TestListCommand_NoDependencies(t *testing.T) {
	t.Run("project.toml exists but is empty", func(t *testing.T) {
		projectTomlContent := `
[package]
name = "test-project"
version = "0.1.0"
description = "A test project."
license = "MIT"
`
		tempDir := setupListTestEnvironment(t, projectTomlContent, "", nil)
		output, err := runListCommand(t, tempDir, "list")

		require.NoError(t, err)
		assert.Contains(t, output, "test-project@0.1.0")
		assert.Contains(t, output, tempDir) // Project path
		assert.Contains(t, output, "dependencies:")
		// Check that there are no dependency lines after "dependencies:"
		lines := strings.Split(strings.TrimSpace(output), "\n")
		depHeaderIndex := -1
		for i, line := range lines {
			if strings.Contains(line, "dependencies:") {
				depHeaderIndex = i
				break
			}
		}
		require.NotEqual(t, -1, depHeaderIndex, "Dependencies header not found")
		assert.Contains(t, output, "No dependencies found in project.toml.", "Expected 'No dependencies found' message")
	})

	t.Run("project.toml with empty dependencies table", func(t *testing.T) {
		projectTomlContent := `
[package]
name = "test-project-empty-deps"
version = "0.1.0"
description = "A test project."
license = "MIT"

[dependencies]
`
		tempDir := setupListTestEnvironment(t, projectTomlContent, "", nil)
		output, err := runListCommand(t, tempDir, "list")

		require.NoError(t, err)
		assert.Contains(t, output, "test-project-empty-deps@0.1.0")
		assert.Contains(t, output, tempDir)
		assert.Contains(t, output, "dependencies:")
		assert.Contains(t, output, "No dependencies found in project.toml.")
	})

	t.Run("project.toml with no dependencies table", func(t *testing.T) {
		projectTomlContent := `
[package]
name = "test-project-no-deps-table"
version = "0.1.0"
`
		tempDir := setupListTestEnvironment(t, projectTomlContent, "", nil)
		output, err := runListCommand(t, tempDir, "list")

		require.NoError(t, err)
		assert.Contains(t, output, "test-project-no-deps-table@0.1.0")
		assert.Contains(t, output, tempDir)
		assert.Contains(t, output, "dependencies:")
		assert.Contains(t, output, "No dependencies found in project.toml.")
	})
}

// Tests list command when project.toml is missing
func TestListCommand_ProjectTomlNotFound(t *testing.T) {
	tempDir := t.TempDir()

	t.Setenv("NO_COLOR", "1")

	_, err := runListCommand(t, tempDir, "list")

	require.Error(t, err, "Expected an error when project.toml is not found")
	require.NotNil(t, err)
	assert.Contains(t, err.Error(), fmt.Sprintf("%s not found in %s, no project configuration loaded", config.ProjectTomlName, "."))
}

// Tests list command with a single dependency that is fully installed and properly locked
func TestListCommand_SingleDependencyFullyInstalledAndLocked(t *testing.T) {
	projectName := "my-lib-project"
	projectVersion := "1.2.3"
	depName := "cool-lib"
	depSource := "github:user/repo/cool-lib.lua@v1.0.0"
	depPath := "libs/cool-lib.lua"
	depContent := "-- cool lib content"
	depHash := "sha256:0567f79f438dda700c93759f193096199983806187765462085899533180c07e"

	projectTomlContent := fmt.Sprintf(`
[package]
name = "%s"
version = "%s"
description = "A test project with one lib."
license = "MIT"

[dependencies.%s]
source = "%s"
path = "%s"
`, projectName, projectVersion, depName, depSource, depPath)

	lockfileContent := fmt.Sprintf(`
api_version = "1"
[package.%s]
source = "https://raw.githubusercontent.com/user/repo/v1.0.0/cool-lib.lua"
path = "%s"
hash = "%s"
`, depName, depPath, depHash)

	depFiles := map[string]string{
		depPath: depContent,
	}

	tempDir := setupListTestEnvironment(t, projectTomlContent, lockfileContent, depFiles)
	resolvedTempDir, err := filepath.EvalSymlinks(tempDir)
	require.NoError(t, err, "Failed to evaluate symlinks for tempDir")

	expectedOutput := fmt.Sprintf("%s@%s %s\n\ndependencies:\n%s %s %s\n",
		projectName, projectVersion, resolvedTempDir,
		depName, depHash, depPath,
	)

	output, err := runListCommand(t, tempDir, "list")

	require.NoError(t, err)
	assert.Equal(t, strings.TrimSpace(expectedOutput), strings.TrimSpace(output))
}

// Tests list command with multiple dependencies in various states:
// - Fully installed and locked
// - In manifest but not locked
// - In manifest and locked but file missing
func TestListCommand_MultipleDependenciesVariedStates(t *testing.T) {
	projectName := "multi-dep-project"
	projectVersion := "0.5.0"

	depAName := "depA"
	depASourceToml := "github:user/repo/depA.lua@v1"
	depAPath := "libs/depA.lua"
	depAContent := "contentA"
	depAHashLock := "sha256:87428fc522803d31065e7bce3cf03fe475096631e5e07bbd7a0fde60c4cf25c7"
	depARawURLLock := "https://raw.githubusercontent.com/user/repo/v1/depA.lua"

	depBName := "depB"
	depBSourceToml := "github:user/repo/depB.lua@main"
	depBPath := "libs/depB.lua"
	depBContent := "contentB"

	depCName := "depC"
	depCSourceToml := "github:user/repo/depC.lua@v2"
	depCPath := "libs/depC.lua"
	depCHashLock := "sha256:2475709fe8a3c28964798420ddd7de39cd9d1930e91035030966877040150863"
	depCRawURLLock := "https://raw.githubusercontent.com/user/repo/v2/depC.lua"

	projectTomlContent := fmt.Sprintf(`
[package]
name = "%s"
version = "%s"

[dependencies.%s]
source = "%s"
path = "%s"

[dependencies.%s]
source = "%s"
path = "%s"

[dependencies.%s]
source = "%s"
path = "%s"
`, projectName, projectVersion,
		depAName, depASourceToml, depAPath,
		depBName, depBSourceToml, depBPath,
		depCName, depCSourceToml, depCPath)

	lockfileContent := fmt.Sprintf(`
api_version = "1"
[package.%s]
source = "%s"
path = "%s"
hash = "%s"

[package.%s]
source = "%s"
path = "%s"
hash = "%s"
`, depAName, depARawURLLock, depAPath, depAHashLock,
		depCName, depCRawURLLock, depCPath, depCHashLock)

	depFiles := map[string]string{
		depAPath: depAContent,
		depBPath: depBContent,
	}

	tempDir := setupListTestEnvironment(t, projectTomlContent, lockfileContent, depFiles)
	resolvedTempDir, err := filepath.EvalSymlinks(tempDir)
	require.NoError(t, err, "Failed to evaluate symlinks for tempDir")

	output, err := runListCommand(t, tempDir, "list")
	require.NoError(t, err)

	outputLines := strings.Split(strings.TrimSpace(output), "\n")
	require.GreaterOrEqual(t, len(outputLines), 5, "Output should have at least 5 lines")

	expectedHeader := fmt.Sprintf("%s@%s %s", projectName, projectVersion, resolvedTempDir)
	assert.Equal(t, expectedHeader, outputLines[0], "Project header should match")

	assert.Equal(t, "dependencies:", outputLines[2], "Dependencies label should match")

	expectedDeps := map[string]bool{
		fmt.Sprintf("%s %s %s", depAName, depAHashLock, depAPath): true,
		fmt.Sprintf("%s %s %s", depBName, "not locked", depBPath): true,
		fmt.Sprintf("%s %s %s", depCName, depCHashLock, depCPath): true,
	}

	for _, line := range outputLines[3:] {
		assert.True(t, expectedDeps[line], fmt.Sprintf("Unexpected dependency entry: %s", line))
	}

	assert.Equal(t, 3, len(outputLines)-3, "Should have exactly 3 dependency entries")
}

// Tests that 'ls' works as an alias for 'list'
func TestListCommand_AliasLs(t *testing.T) {
	projectName := "alias-test-project"
	projectVersion := "1.0.0"
	depName := "lib-for-ls"
	depSource := "github:user/repo/lib-for-ls.lua@v0.1"
	depPath := "modules/lib-for-ls.lua"
	depContent := "function lib_for_ls() return 'ls alias test' end"
	depHash := "sha256:b0d9a380789173d734093af007772d31790ead09999b891d180099160e27f9a0"

	projectTomlContent := fmt.Sprintf(`
[package]
name = "%s"
version = "%s"
[dependencies.%s]
source = "%s"
path = "%s"
`, projectName, projectVersion, depName, depSource, depPath)

	lockfileContent := fmt.Sprintf(`
api_version = "1"
[package.%s]
source = "https://raw.githubusercontent.com/user/repo/v0.1/lib-for-ls.lua"
path = "%s"
hash = "%s"
`, depName, depPath, depHash)

	depFiles := map[string]string{
		depPath: depContent,
	}

	tempDir := setupListTestEnvironment(t, projectTomlContent, lockfileContent, depFiles)
	resolvedTempDir, err := filepath.EvalSymlinks(tempDir)
	require.NoError(t, err, "Failed to evaluate symlinks for tempDir")

	expectedOutput := fmt.Sprintf("%s@%s %s\n\ndependencies:\n%s %s %s\n",
		projectName, projectVersion, resolvedTempDir,
		depName, depHash, depPath,
	)

	output, err := runListCommand(t, tempDir, "ls")

	require.NoError(t, err)
	assert.Equal(t, strings.TrimSpace(expectedOutput), strings.TrimSpace(output), "Output of 'almd ls' should match expected 'almd list' output")
}
