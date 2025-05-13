// Package remove provides functionality to remove dependencies from Almandine projects.
package remove

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/BurntSushi/toml"
	"github.com/nightconcept/almandine/internal/core/config"
	"github.com/nightconcept/almandine/internal/core/lockfile"
	"github.com/nightconcept/almandine/internal/core/project"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/urfave/cli/v2"
)

// TestRemoveCommand_SuccessfulRemoval verifies that a dependency can be completely
// removed from project.toml, almd-lock.toml, and the filesystem.
func TestRemoveCommand_SuccessfulRemoval(t *testing.T) {
	originalWd, err := os.Getwd()
	t.Logf("Test starting in directory: %s", originalWd)
	require.NoError(t, err, "Failed to get current working directory")
	defer func() {
		t.Logf("Test cleanup: restoring directory to %s", originalWd)
		require.NoError(t, os.Chdir(originalWd), "Failed to restore original working directory")
	}()

	projectToml := `
[package]
name = "test-project"
version = "0.1.0"

[dependencies]
testlib = { source = "github:user/repo/file.lua@abc123", path = "libs/testlib.lua" }
`

	lockToml := `
api_version = "1"

[package.testlib]
source = "https://raw.githubusercontent.com/user/repo/abc123/file.lua"
path = "libs/testlib.lua"
hash = "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
`

	depFiles := map[string]string{
		"libs/testlib.lua": "-- Test dependency content",
	}

	tempDir := setupRemoveTestEnvironment(t, projectToml, lockToml, depFiles)

	if _, err := os.Stat(filepath.Join(tempDir, "project.toml")); err != nil {
		t.Logf("After setup - project.toml status: %v", err)
	} else {
		t.Log("After setup - project.toml exists")
	}

	err = os.Chdir(tempDir)
	t.Logf("Changed to temp directory: %s", tempDir)
	require.NoError(t, err, "Failed to change to temporary directory")

	err = runRemoveCommand(t, tempDir, "testlib")
	require.NoError(t, err)

	projContent, err := os.ReadFile(filepath.Join(tempDir, "project.toml"))
	require.NoError(t, err)
	assert.NotContains(t, string(projContent), "testlib")

	var proj struct {
		Dependencies map[string]interface{} `toml:"dependencies"`
	}
	err = toml.Unmarshal(projContent, &proj)
	require.NoError(t, err)
	assert.NotContains(t, proj.Dependencies, "testlib")

	lockContent, err := os.ReadFile(filepath.Join(tempDir, "almd-lock.toml"))
	require.NoError(t, err)
	assert.NotContains(t, string(lockContent), "testlib")

	var lock struct {
		Package map[string]interface{} `toml:"package"`
	}
	err = toml.Unmarshal(lockContent, &lock)
	require.NoError(t, err)
	assert.NotContains(t, lock.Package, "testlib")

	_, err = os.Stat(filepath.Join(tempDir, "libs", "testlib.lua"))
	assert.True(t, os.IsNotExist(err), "Dependency file should be deleted")

	_, err = os.Stat(filepath.Join(tempDir, "libs"))
	assert.True(t, os.IsNotExist(err), "Empty libs directory should be removed")
}

// TestRemove_DependencyNotFound verifies the command fails appropriately when
// attempting to remove a non-existent dependency, ensuring other dependencies
// remain untouched.
func TestRemove_DependencyNotFound(t *testing.T) {
	originalWd, err := os.Getwd()
	t.Logf("Test starting in directory: %s", originalWd)
	require.NoError(t, err, "Failed to get current working directory")
	defer func() {
		t.Logf("Test cleanup: restoring directory to %s", originalWd)
		require.NoError(t, os.Chdir(originalWd), "Failed to restore original working directory")
	}()

	tempDir := t.TempDir()

	projectToml := `
[package]
name = "test-project"
version = "0.1.0"

[dependencies]
existing-dep = { source = "github:user/repo/file.lua", path = "libs/existing-dep.lua" }
`
	err = os.WriteFile(filepath.Join(tempDir, "project.toml"), []byte(projectToml), 0644)
	require.NoError(t, err)

	lockfileToml := `
api_version = "1"

[package.existing-dep]
source = "https://raw.githubusercontent.com/user/repo/main/file.lua"
path = "libs/existing-dep.lua"
hash = "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
`
	err = os.WriteFile(filepath.Join(tempDir, "almd-lock.toml"), []byte(lockfileToml), 0644)
	require.NoError(t, err)

	existingDepDir := filepath.Join(tempDir, "libs")
	err = os.MkdirAll(existingDepDir, 0755)
	require.NoError(t, err)
	err = os.WriteFile(filepath.Join(existingDepDir, "existing-dep.lua"), []byte("-- test content"), 0644)
	require.NoError(t, err)

	err = os.Chdir(tempDir)
	t.Logf("Changed to temp directory: %s", tempDir)
	require.NoError(t, err, "Failed to change to temporary directory")

	err = runRemoveCommand(t, tempDir, "non-existent-dep")

	assert.Error(t, err)
	assert.Equal(t, "Error: dependency 'non-existent-dep' not found in project.toml", err.Error())
	assert.Equal(t, 1, err.(cli.ExitCoder).ExitCode())

	currentProjectToml, err := os.ReadFile(filepath.Join(tempDir, "project.toml"))
	require.NoError(t, err)
	assert.Equal(t, string(projectToml), string(currentProjectToml))

	currentLockfileToml, err := os.ReadFile(filepath.Join(tempDir, "almd-lock.toml"))
	require.NoError(t, err)
	assert.Equal(t, string(lockfileToml), string(currentLockfileToml))

	_, err = os.Stat(filepath.Join(existingDepDir, "existing-dep.lua"))
	assert.NoError(t, err, "existing dependency file should not be deleted")
}

// TestRemoveCommand_DepFileMissing_StillUpdatesManifests verifies that removal
// succeeds and updates manifests even when the dependency file is missing from
// the filesystem, which can happen if files were manually deleted.
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

	// Expect no fatal error, as remove.go should gracefully handle
	// os.IsNotExist when attempting to delete the already missing file.
	err = runRemoveCommand(t, tempDir, "missinglib")
	require.NoError(t, err, "runRemoveCommand should not return a fatal error when dep file is missing")

	var projData struct {
		Dependencies map[string]project.Dependency `toml:"dependencies"`
	}
	projBytes, err := os.ReadFile(filepath.Join(tempDir, config.ProjectTomlName))
	require.NoError(t, err)
	err = toml.Unmarshal(projBytes, &projData)
	require.NoError(t, err)
	assert.NotContains(t, projData.Dependencies, "missinglib", "missinglib should be removed from project.toml")
	assert.Contains(t, projData.Dependencies, "anotherlib", "anotherlib should still exist in project.toml")

	var lockData struct {
		Package map[string]lockfile.PackageEntry `toml:"package"`
	}
	lockBytes, err := os.ReadFile(filepath.Join(tempDir, lockfile.LockfileName))
	require.NoError(t, err)
	err = toml.Unmarshal(lockBytes, &lockData)
	require.NoError(t, err)
	assert.NotContains(t, lockData.Package, "missinglib", "missinglib should be removed from almd-lock.toml")
	assert.Contains(t, lockData.Package, "anotherlib", "anotherlib should still exist in almd-lock.toml")

	_, err = os.Stat(filepath.Join(tempDir, "libs", "anotherlib.lua"))
	assert.NoError(t, err, "anotherlib.lua should still exist")

	_, err = os.Stat(filepath.Join(tempDir, "libs", "missinglib.lua"))
	assert.True(t, os.IsNotExist(err), "missinglib.lua should not exist")
}

// TestRemoveCommand_ProjectTomlNotFound verifies the command fails appropriately
// when project.toml is missing from the working directory.
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

	err = runRemoveCommand(t, tempDir, "any-dependency-name")

	require.Error(t, err, "Expected an error when project.toml is not found")

	exitErr, ok := err.(cli.ExitCoder)
	require.True(t, ok, "Error should be a cli.ExitCoder")

	assert.Equal(t, 1, exitErr.ExitCode(), "Expected exit code 1")
	// Error message should now come from config.LoadProjectToml when project.toml is not found.
	assert.Contains(t, exitErr.Error(), "Error: failed to load project.toml:", "Error message prefix mismatch")
	// Don't check for specific OS error message text which varies between platforms
}

// TestRemoveCommand_ManifestOnlyDependency verifies the command handles dependencies
// that exist only in project.toml but not in almd-lock.toml.
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

	err = runRemoveCommand(t, tempDir, "manifestonlylib")
	require.NoError(t, err, "runRemoveCommand should not return a fatal error for manifest-only dependency")

	var projData struct {
		Dependencies map[string]project.Dependency `toml:"dependencies"`
	}
	projBytes, err := os.ReadFile(filepath.Join(tempDir, config.ProjectTomlName))
	require.NoError(t, err)
	err = toml.Unmarshal(projBytes, &projData)
	require.NoError(t, err)
	assert.NotContains(t, projData.Dependencies, "manifestonlylib", "manifestonlylib should be removed from project.toml")
	assert.Contains(t, projData.Dependencies, "anotherlib", "anotherlib should still exist in project.toml")

	var lockData struct {
		Package map[string]lockfile.PackageEntry `toml:"package"`
	}
	lockBytes, err := os.ReadFile(filepath.Join(tempDir, lockfile.LockfileName))
	require.NoError(t, err)
	err = toml.Unmarshal(lockBytes, &lockData)
	require.NoError(t, err)
	assert.NotContains(t, lockData.Package, "manifestonlylib", "manifestonlylib should not be in almd-lock.toml")
	assert.Contains(t, lockData.Package, "anotherlib", "anotherlib should still exist in almd-lock.toml")

	_, err = os.Stat(filepath.Join(tempDir, "libs", "manifestonlylib.lua"))
	assert.True(t, os.IsNotExist(err), "manifestonlylib.lua should be deleted")

	_, err = os.Stat(filepath.Join(tempDir, "libs", "anotherlib.lua"))
	assert.NoError(t, err, "anotherlib.lua should still exist")

	// Verify 'libs' directory for 'manifestonlylib.lua' was removed if it became empty
	// (In this case, 'libs' dir will still contain 'anotherlib.lua', so it won't be removed)
	// If 'anotherlib.lua' was also removed in a different test, then 'libs' would be gone.
	// Here, we just ensure 'manifestonlylib.lua' is gone.
}

// TestRemoveCommand_EmptyProjectToml verifies the command fails appropriately
// when project.toml exists but contains no dependencies.
func TestRemoveCommand_EmptyProjectToml(t *testing.T) {
	originalWd, err := os.Getwd()
	require.NoError(t, err, "Failed to get current working directory")
	defer func() {
		require.NoError(t, os.Chdir(originalWd), "Failed to restore original working directory")
	}()

	tempDir := setupRemoveTestEnvironment(t, "", "", nil)

	err = os.Chdir(tempDir)
	require.NoError(t, err, "Failed to change to temporary directory")

	depNameToRemove := "any-dep"

	err = runRemoveCommand(t, tempDir, depNameToRemove)

	require.Error(t, err, "Expected an error when project.toml is empty")

	exitErr, ok := err.(cli.ExitCoder)
	require.True(t, ok, "Error should be a cli.ExitCoder")
	assert.Equal(t, 1, exitErr.ExitCode(), "Expected exit code 1")
	// With the changes in remove.go, if project.toml is empty (or has no [dependencies] table),
	// it should return "Error: no dependencies found in project.toml"
	assert.Equal(t, "Error: no dependencies found in project.toml", exitErr.Error())

	projectTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	projectTomlBytes, err := os.ReadFile(projectTomlPath)
	require.NoError(t, err, "Failed to read project.toml after command")
	assert.Equal(t, "", string(projectTomlBytes), "project.toml should remain empty")

	lockfilePath := filepath.Join(tempDir, lockfile.LockfileName)
	lockfileBytes, err := os.ReadFile(lockfilePath)
	require.NoError(t, err, "Failed to read almd-lock.toml after command")
	assert.Equal(t, "", string(lockfileBytes), "almd-lock.toml should remain empty")
}

// setupRemoveTestEnvironment creates a temporary test environment with the specified
// initial content for project.toml and almd-lock.toml, and any dependency files.
// It returns the path to the temporary directory.
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

// runRemoveCommand executes the remove command with the given arguments in the specified
// working directory.
func runRemoveCommand(t *testing.T, workDir string, removeCmdArgs ...string) error {
	t.Helper()

	// Remove working directory handling from here since it's now handled in the test
	app := &cli.App{
		Name: "almd-test-remove",
		Commands: []*cli.Command{
			RemoveCmd(),
		},
		Writer:         os.Stderr,
		ErrWriter:      os.Stderr,
		ExitErrHandler: func(context *cli.Context, err error) {},
	}

	cliArgs := []string{"almd-test-remove", "remove"}
	cliArgs = append(cliArgs, removeCmdArgs...)

	return app.Run(cliArgs)
}
