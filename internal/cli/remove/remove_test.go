package remove

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/BurntSushi/toml"
	"github.com/nightconcept/almandine/internal/core/config"
	"github.com/nightconcept/almandine/internal/core/lockfile"
	"github.com/nightconcept/almandine/internal/core/project" // Added import
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/urfave/cli/v2"
)

func TestRemoveCommand_SuccessfulRemoval(t *testing.T) {
	// Store original working directory and restore it after test
	originalWd, err := os.Getwd()
	t.Logf("Test starting in directory: %s", originalWd)
	require.NoError(t, err, "Failed to get current working directory")
	defer func() {
		t.Logf("Test cleanup: restoring directory to %s", originalWd)
		require.NoError(t, os.Chdir(originalWd), "Failed to restore original working directory")
	}()

	// Create initial project.toml content
	projectToml := `
[package]
name = "test-project"
version = "0.1.0"

[dependencies]
testlib = { source = "github:user/repo/file.lua@abc123", path = "libs/testlib.lua" }
`

	// Create initial lockfile content
	lockToml := `
api_version = "1"

[package.testlib]
source = "https://raw.githubusercontent.com/user/repo/abc123/file.lua"
path = "libs/testlib.lua"
hash = "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
`

	// Create map of dependency files to create
	depFiles := map[string]string{
		"libs/testlib.lua": "-- Test dependency content",
	}

	// Set up test environment
	tempDir := setupRemoveTestEnvironment(t, projectToml, lockToml, depFiles)

	// After setup, verify files exist
	if _, err := os.Stat(filepath.Join(tempDir, "project.toml")); err != nil {
		t.Logf("After setup - project.toml status: %v", err)
	} else {
		t.Log("After setup - project.toml exists")
	}

	// Change to temp directory before running the test
	err = os.Chdir(tempDir)
	t.Logf("Changed to temp directory: %s", tempDir)
	require.NoError(t, err, "Failed to change to temporary directory")

	// Run the remove command
	err = runRemoveCommand(t, tempDir, "testlib")
	require.NoError(t, err)

	// Verify project.toml no longer contains the dependency
	projContent, err := os.ReadFile(filepath.Join(tempDir, "project.toml"))
	require.NoError(t, err)
	assert.NotContains(t, string(projContent), "testlib")

	// Parse project.toml to verify dependency is gone
	var proj struct {
		Dependencies map[string]interface{} `toml:"dependencies"`
	}
	err = toml.Unmarshal(projContent, &proj)
	require.NoError(t, err)
	assert.NotContains(t, proj.Dependencies, "testlib")

	// Verify almd-lock.toml no longer contains the dependency
	lockContent, err := os.ReadFile(filepath.Join(tempDir, "almd-lock.toml"))
	require.NoError(t, err)
	assert.NotContains(t, string(lockContent), "testlib")

	// Parse lock file to verify dependency is gone
	var lock struct {
		Package map[string]interface{} `toml:"package"`
	}
	err = toml.Unmarshal(lockContent, &lock)
	require.NoError(t, err)
	assert.NotContains(t, lock.Package, "testlib")

	// Verify dependency file is deleted
	_, err = os.Stat(filepath.Join(tempDir, "libs", "testlib.lua"))
	assert.True(t, os.IsNotExist(err), "Dependency file should be deleted")

	// Verify libs directory is removed (since it should be empty now)
	_, err = os.Stat(filepath.Join(tempDir, "libs"))
	assert.True(t, os.IsNotExist(err), "Empty libs directory should be removed")
}

func TestRemove_DependencyNotFound(t *testing.T) {
	// Store original working directory
	originalWd, err := os.Getwd()
	t.Logf("Test starting in directory: %s", originalWd)
	require.NoError(t, err, "Failed to get current working directory")
	defer func() {
		t.Logf("Test cleanup: restoring directory to %s", originalWd)
		require.NoError(t, os.Chdir(originalWd), "Failed to restore original working directory")
	}()

	// Create a temp dir for the test
	tempDir := t.TempDir()

	// Create a project.toml without the dependency we'll try to remove
	projectToml := `
[package]
name = "test-project"
version = "0.1.0"

[dependencies]
existing-dep = { source = "github:user/repo/file.lua", path = "libs/existing-dep.lua" }
`
	err = os.WriteFile(filepath.Join(tempDir, "project.toml"), []byte(projectToml), 0644)
	require.NoError(t, err)

	// Create a lockfile that matches project.toml
	lockfileToml := `
api_version = "1"

[package.existing-dep]
source = "https://raw.githubusercontent.com/user/repo/main/file.lua"
path = "libs/existing-dep.lua"
hash = "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
`
	err = os.WriteFile(filepath.Join(tempDir, "almd-lock.toml"), []byte(lockfileToml), 0644)
	require.NoError(t, err)

	// Create the existing dependency file to ensure we don't accidentally delete it
	existingDepDir := filepath.Join(tempDir, "libs")
	err = os.MkdirAll(existingDepDir, 0755)
	require.NoError(t, err)
	err = os.WriteFile(filepath.Join(existingDepDir, "existing-dep.lua"), []byte("-- test content"), 0644)
	require.NoError(t, err)

	// Change to temp directory before running command
	err = os.Chdir(tempDir)
	t.Logf("Changed to temp directory: %s", tempDir)
	require.NoError(t, err, "Failed to change to temporary directory")

	// Execute the remove command
	err = runRemoveCommand(t, tempDir, "non-existent-dep")

	// Verify expectations
	assert.Error(t, err)
	assert.Equal(t, "Error: Dependency 'non-existent-dep' not found in project.toml.", err.Error())
	assert.Equal(t, 1, err.(cli.ExitCoder).ExitCode())

	// Verify project.toml and almd-lock.toml remain unchanged
	currentProjectToml, err := os.ReadFile(filepath.Join(tempDir, "project.toml"))
	require.NoError(t, err)
	assert.Equal(t, string(projectToml), string(currentProjectToml))

	currentLockfileToml, err := os.ReadFile(filepath.Join(tempDir, "almd-lock.toml"))
	require.NoError(t, err)
	assert.Equal(t, string(lockfileToml), string(currentLockfileToml))

	// Verify the existing dependency file was not touched
	_, err = os.Stat(filepath.Join(existingDepDir, "existing-dep.lua"))
	assert.NoError(t, err, "existing dependency file should not be deleted")
}

func TestRemoveCommand_DepFileMissing_StillUpdatesManifests(t *testing.T) {
	originalWd, err := os.Getwd()
	require.NoError(t, err)
	defer func() {
		require.NoError(t, os.Chdir(originalWd))
	}()

	projectTomlContent := `
[package]
name = "test-project-missing-file"
version = "0.1.0"

[dependencies]
missinglib = { source = "github:user/repo/missing.lua@def456", path = "libs/missinglib.lua" }
anotherlib = { source = "github:user/repo/another.lua@ghi789", path = "libs/anotherlib.lua" }
`
	lockTomlContent := `
api_version = "1"

[package.missinglib]
source = "https://raw.githubusercontent.com/user/repo/def456/missing.lua"
path = "libs/missinglib.lua"
hash = "sha256:123"

[package.anotherlib]
source = "https://raw.githubusercontent.com/user/repo/ghi789/another.lua"
path = "libs/anotherlib.lua"
hash = "sha256:456"
`
	// Setup environment: Create project.toml and almd-lock.toml
	// but DO NOT create the actual 'missinglib.lua' file.
	// Only create 'anotherlib.lua' to ensure other files are not affected.
	depFilesToCreate := map[string]string{
		"libs/anotherlib.lua": "-- another lib content",
	}
	tempDir := setupRemoveTestEnvironment(t, projectTomlContent, lockTomlContent, depFilesToCreate)

	err = os.Chdir(tempDir)
	require.NoError(t, err, "Failed to change to temporary directory")

	// Run the remove command for 'missinglib'
	// This should not return an error that stops processing,
	// as remove.go handles os.IsNotExist for the file deletion.
	err = runRemoveCommand(t, tempDir, "missinglib")
	require.NoError(t, err, "runRemoveCommand should not return a fatal error when dep file is missing")

	// Verify project.toml is updated (missinglib removed, anotherlib remains)
	var projData struct {
		Dependencies map[string]project.Dependency `toml:"dependencies"`
	}
	projBytes, err := os.ReadFile(filepath.Join(tempDir, config.ProjectTomlName))
	require.NoError(t, err)
	err = toml.Unmarshal(projBytes, &projData)
	require.NoError(t, err)
	assert.NotContains(t, projData.Dependencies, "missinglib", "missinglib should be removed from project.toml")
	assert.Contains(t, projData.Dependencies, "anotherlib", "anotherlib should still exist in project.toml")

	// Verify almd-lock.toml is updated (missinglib removed, anotherlib remains)
	var lockData struct {
		Package map[string]lockfile.PackageEntry `toml:"package"`
	}
	lockBytes, err := os.ReadFile(filepath.Join(tempDir, lockfile.LockfileName))
	require.NoError(t, err)
	err = toml.Unmarshal(lockBytes, &lockData)
	require.NoError(t, err)
	assert.NotContains(t, lockData.Package, "missinglib", "missinglib should be removed from almd-lock.toml")
	assert.Contains(t, lockData.Package, "anotherlib", "anotherlib should still exist in almd-lock.toml")

	// Verify the 'anotherlib.lua' file still exists
	_, err = os.Stat(filepath.Join(tempDir, "libs", "anotherlib.lua"))
	assert.NoError(t, err, "anotherlib.lua should still exist")

	// Verify 'missinglib.lua' (which never existed) is still not there
	_, err = os.Stat(filepath.Join(tempDir, "libs", "missinglib.lua"))
	assert.True(t, os.IsNotExist(err), "missinglib.lua should not exist")
}

func TestRemoveCommand_ProjectTomlNotFound(t *testing.T) {
	originalWd, err := os.Getwd()
	require.NoError(t, err, "Failed to get current working directory")
	defer func() {
		require.NoError(t, os.Chdir(originalWd), "Failed to restore original working directory")
	}()

	tempDir := t.TempDir()

	// Change to temp directory (which has no project.toml)
	err = os.Chdir(tempDir)
	require.NoError(t, err, "Failed to change to temporary directory: %s", tempDir)

	// Attempt to remove a dependency
	err = runRemoveCommand(t, tempDir, "any-dependency-name")

	// Verify the error
	require.Error(t, err, "Expected an error when project.toml is not found")

	// Check for cli.ExitCoder interface for specific exit code and message
	exitErr, ok := err.(cli.ExitCoder)
	require.True(t, ok, "Error should be a cli.ExitCoder")

	assert.Equal(t, 1, exitErr.ExitCode(), "Expected exit code 1")
	// Error message should now come from config.LoadProjectToml when project.toml is not found.
	assert.Contains(t, exitErr.Error(), "Error: Failed to load project.toml:", "Error message prefix mismatch")
	// Don't check for specific OS error message text which varies between platforms
}

func TestRemoveCommand_ManifestOnlyDependency(t *testing.T) {
	originalWd, err := os.Getwd()
	require.NoError(t, err)
	defer func() {
		require.NoError(t, os.Chdir(originalWd))
	}()

	projectTomlContent := `
[package]
name = "test-project-manifest-only"
version = "0.1.0"

[dependencies]
manifestonlylib = { source = "github:user/repo/manifestonly.lua@jkl012", path = "libs/manifestonlylib.lua" }
anotherlib = { source = "github:user/repo/another.lua@mno345", path = "libs/anotherlib.lua" }
`
	// Lockfile is empty or does not contain 'manifestonlylib'
	// It might contain other unrelated dependencies.
	lockTomlContent := `
api_version = "1"

[package.anotherlib]
source = "https://raw.githubusercontent.com/user/repo/mno345/another.lua"
path = "libs/anotherlib.lua"
hash = "sha256:789"
`
	depFilesToCreate := map[string]string{
		"libs/manifestonlylib.lua": "-- manifest only lib content",
		"libs/anotherlib.lua":      "-- another lib content",
	}
	tempDir := setupRemoveTestEnvironment(t, projectTomlContent, lockTomlContent, depFilesToCreate)

	err = os.Chdir(tempDir)
	require.NoError(t, err, "Failed to change to temporary directory")

	// Run the remove command for 'manifestonlylib'
	err = runRemoveCommand(t, tempDir, "manifestonlylib")
	require.NoError(t, err, "runRemoveCommand should not return a fatal error for manifest-only dependency")

	// Verify project.toml is updated (manifestonlylib removed, anotherlib remains)
	var projData struct {
		Dependencies map[string]project.Dependency `toml:"dependencies"`
	}
	projBytes, err := os.ReadFile(filepath.Join(tempDir, config.ProjectTomlName))
	require.NoError(t, err)
	err = toml.Unmarshal(projBytes, &projData)
	require.NoError(t, err)
	assert.NotContains(t, projData.Dependencies, "manifestonlylib", "manifestonlylib should be removed from project.toml")
	assert.Contains(t, projData.Dependencies, "anotherlib", "anotherlib should still exist in project.toml")

	// Verify almd-lock.toml is processed (manifestonlylib was not there, anotherlib remains)
	var lockData struct {
		Package map[string]lockfile.PackageEntry `toml:"package"`
	}
	lockBytes, err := os.ReadFile(filepath.Join(tempDir, lockfile.LockfileName))
	require.NoError(t, err)
	err = toml.Unmarshal(lockBytes, &lockData)
	require.NoError(t, err)
	assert.NotContains(t, lockData.Package, "manifestonlylib", "manifestonlylib should not be in almd-lock.toml")
	assert.Contains(t, lockData.Package, "anotherlib", "anotherlib should still exist in almd-lock.toml")

	// Verify the 'manifestonlylib.lua' file is deleted
	_, err = os.Stat(filepath.Join(tempDir, "libs", "manifestonlylib.lua"))
	assert.True(t, os.IsNotExist(err), "manifestonlylib.lua should be deleted")

	// Verify the 'anotherlib.lua' file still exists
	_, err = os.Stat(filepath.Join(tempDir, "libs", "anotherlib.lua"))
	assert.NoError(t, err, "anotherlib.lua should still exist")

	// Verify 'libs' directory for 'manifestonlylib.lua' was removed if it became empty
	// (In this case, 'libs' dir will still contain 'anotherlib.lua', so it won't be removed)
	// If 'anotherlib.lua' was also removed in a different test, then 'libs' would be gone.
	// Here, we just ensure 'manifestonlylib.lua' is gone.
}

func TestRemoveCommand_EmptyProjectToml(t *testing.T) {
	originalWd, err := os.Getwd()
	require.NoError(t, err, "Failed to get current working directory")
	defer func() {
		require.NoError(t, os.Chdir(originalWd), "Failed to restore original working directory")
	}()

	// Setup: Temp dir with empty project.toml and empty almd-lock.toml.
	tempDir := setupRemoveTestEnvironment(t, "", "", nil)

	err = os.Chdir(tempDir)
	require.NoError(t, err, "Failed to change to temporary directory")

	depNameToRemove := "any-dep"

	// Execute: almd remove <dependency_name>
	err = runRemoveCommand(t, tempDir, depNameToRemove)

	// Verify: Command returns an error indicating dependency not found
	require.Error(t, err, "Expected an error when project.toml is empty")

	exitErr, ok := err.(cli.ExitCoder)
	require.True(t, ok, "Error should be a cli.ExitCoder")
	assert.Equal(t, 1, exitErr.ExitCode(), "Expected exit code 1")
	// With the changes in remove.go, if project.toml is empty (or has no [dependencies] table),
	// it should return "Error: No dependencies found in project.toml."
	assert.Equal(t, "Error: No dependencies found in project.toml.", exitErr.Error())

	// Verify: files remain empty or unchanged.
	projectTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	projectTomlBytes, err := os.ReadFile(projectTomlPath)
	require.NoError(t, err, "Failed to read project.toml after command")
	assert.Equal(t, "", string(projectTomlBytes), "project.toml should remain empty")

	lockfilePath := filepath.Join(tempDir, lockfile.LockfileName)
	lockfileBytes, err := os.ReadFile(lockfilePath)
	require.NoError(t, err, "Failed to read almd-lock.toml after command")
	assert.Equal(t, "", string(lockfileBytes), "almd-lock.toml should remain empty")
}

// Helper Functions
func setupRemoveTestEnvironment(t *testing.T, initialProjectTomlContent string, initialLockfileContent string, depFiles map[string]string) (tempDir string) {
	t.Helper()
	tempDir = t.TempDir()

	// Always create project.toml, using provided content (empty string means empty file)
	projectTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	err := os.WriteFile(projectTomlPath, []byte(initialProjectTomlContent), 0644)
	require.NoError(t, err, "Failed to write project.toml")

	// Always create almd-lock.toml, using provided content (empty string means empty file)
	lockfilePath := filepath.Join(tempDir, lockfile.LockfileName)
	err = os.WriteFile(lockfilePath, []byte(initialLockfileContent), 0644)
	require.NoError(t, err, "Failed to write almd-lock.toml")

	for relPath, content := range depFiles {
		absPath := filepath.Join(tempDir, relPath)
		err := os.MkdirAll(filepath.Dir(absPath), 0755)
		require.NoError(t, err, "Failed to create directory for dependency file: %s", filepath.Dir(absPath))
		err = os.WriteFile(absPath, []byte(content), 0644)
		require.NoError(t, err, "Failed to write dependency file: %s", absPath)
	}

	return tempDir
}

func runRemoveCommand(t *testing.T, workDir string, removeCmdArgs ...string) error {
	t.Helper()

	// Remove working directory handling from here since it's now handled in the test
	app := &cli.App{
		Name: "almd-test-remove",
		Commands: []*cli.Command{
			RemoveCommand(),
		},
		Writer:         os.Stderr,
		ErrWriter:      os.Stderr,
		ExitErrHandler: func(context *cli.Context, err error) {},
	}

	cliArgs := []string{"almd-test-remove", "remove"}
	cliArgs = append(cliArgs, removeCmdArgs...)

	return app.Run(cliArgs)
}
