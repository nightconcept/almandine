// Package lockfile_test contains tests for the lockfile package.
package lockfile_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/nightconcept/almandine/internal/core/lockfile"
)

func TestNewLockfile(t *testing.T) {
	t.Parallel()
	lf := lockfile.New()
	assert.NotNil(t, lf, "New lockfile should not be nil")
	assert.Equal(t, lockfile.APIVersion, lf.ApiVersion, "API version mismatch")
	assert.NotNil(t, lf.Package, "Packages map should be initialized")
	assert.Empty(t, lf.Package, "Packages map should be empty initially")
}

func TestLoadLockfile_NotFound(t *testing.T) {
	t.Parallel()
	tempDir := t.TempDir()

	lf, err := lockfile.Load(tempDir)
	require.NoError(t, err, "Load should not return error if lockfile not found")
	assert.NotNil(t, lf, "Loaded lockfile should not be nil even if not found")
	assert.Equal(t, lockfile.APIVersion, lf.ApiVersion, "API version mismatch for new lockfile")
	assert.Empty(t, lf.Package, "Packages map should be empty for new lockfile")
}

func TestLoadLockfile_Valid(t *testing.T) {
	t.Parallel()
	tempDir := t.TempDir()
	lockfilePath := filepath.Join(tempDir, lockfile.LockfileName)

	content := `
api_version = "1"
[package.mylib]
  source = "http://example.com/mylib.lua"
  path = "libs/mylib.lua"
  hash = "sha256:abcdef123456"
`
	err := os.WriteFile(lockfilePath, []byte(content), 0600)
	require.NoError(t, err, "Failed to write mock lockfile")

	lf, err := lockfile.Load(tempDir)
	require.NoError(t, err, "Load returned an unexpected error for valid lockfile")
	assert.NotNil(t, lf)
	assert.Equal(t, "1", lf.ApiVersion)
	require.Contains(t, lf.Package, "mylib")
	assert.Equal(t, "http://example.com/mylib.lua", lf.Package["mylib"].Source)
	assert.Equal(t, "libs/mylib.lua", lf.Package["mylib"].Path)
	assert.Equal(t, "sha256:abcdef123456", lf.Package["mylib"].Hash)
}

func TestLoadLockfile_InvalidToml(t *testing.T) {
	t.Parallel()
	tempDir := t.TempDir()
	lockfilePath := filepath.Join(tempDir, lockfile.LockfileName)

	content := `api_version = "1" this is invalid toml`
	err := os.WriteFile(lockfilePath, []byte(content), 0600)
	require.NoError(t, err, "Failed to write mock invalid lockfile")

	_, err = lockfile.Load(tempDir)
	require.Error(t, err, "Load should return an error for invalid TOML")
	assert.Contains(t, err.Error(), "failed to decode lockfile", "Error message mismatch")
}

func TestLoadLockfile_EmptyFile(t *testing.T) {
	t.Parallel()
	tempDir := t.TempDir()
	lockfilePath := filepath.Join(tempDir, lockfile.LockfileName)

	err := os.WriteFile(lockfilePath, []byte(""), 0600) // Empty file
	require.NoError(t, err, "Failed to write empty mock lockfile")

	lf, err := lockfile.Load(tempDir)
	require.NoError(t, err, "Load should not error on an empty file")
	assert.NotNil(t, lf)
	assert.Equal(t, lockfile.APIVersion, lf.ApiVersion, "API version should default for empty file")
	assert.NotNil(t, lf.Package)
	assert.Empty(t, lf.Package, "Packages should be empty for empty file")
}

func TestLoadLockfile_MissingApiVersion(t *testing.T) {
	t.Parallel()
	tempDir := t.TempDir()
	lockfilePath := filepath.Join(tempDir, lockfile.LockfileName)
	content := `
[package.mylib]
  source = "http://example.com/mylib.lua"
  path = "libs/mylib.lua"
  hash = "sha256:abcdef123456"
`
	err := os.WriteFile(lockfilePath, []byte(content), 0600)
	require.NoError(t, err, "Failed to write mock lockfile without api_version")

	lf, err := lockfile.Load(tempDir)
	require.NoError(t, err, "Load should not error if api_version is missing")
	assert.Equal(t, lockfile.APIVersion, lf.ApiVersion, "API version should default if missing")
	require.Contains(t, lf.Package, "mylib")
}

func TestSaveLockfile_New(t *testing.T) {
	t.Parallel()
	tempDir := t.TempDir()
	lf := lockfile.New()
	lf.Package["dep1"] = lockfile.PackageEntry{
		Source: "http://example.com/dep1.zip",
		Path:   "vendor/dep1",
		Hash:   "sha256:123",
	}

	err := lockfile.Save(tempDir, lf)
	require.NoError(t, err, "Save returned an unexpected error")

	lockfilePath := filepath.Join(tempDir, lockfile.LockfileName)
	_, err = os.Stat(lockfilePath)
	require.NoError(t, err, "Lockfile was not created")

	loadedLf, err := lockfile.Load(tempDir)
	require.NoError(t, err, "Failed to load saved lockfile")
	assert.Equal(t, lf, loadedLf, "Saved and loaded lockfiles do not match")
}

func TestSaveLockfile_Overwrite(t *testing.T) {
	t.Parallel()
	tempDir := t.TempDir()
	lockfilePath := filepath.Join(tempDir, lockfile.LockfileName)

	// Initial content
	initialContent := `api_version = "0.5"`
	err := os.WriteFile(lockfilePath, []byte(initialContent), 0600)
	require.NoError(t, err, "Failed to write initial mock lockfile")

	lfToSave := lockfile.New() // This will have APIVersion = "1"
	lfToSave.Package["newdep"] = lockfile.PackageEntry{
		Source: "http://example.com/newdep.tar.gz",
		Path:   "deps/newdep",
		Hash:   "sha256:abc",
	}

	err = lockfile.Save(tempDir, lfToSave)
	require.NoError(t, err, "Save returned an unexpected error when overwriting")

	loadedLf, err := lockfile.Load(tempDir)
	require.NoError(t, err, "Failed to load overwritten lockfile")
	assert.Equal(t, lfToSave.ApiVersion, loadedLf.ApiVersion)
	assert.Equal(t, lfToSave.Package["newdep"], loadedLf.Package["newdep"])
}

func TestAddOrUpdatePackage(t *testing.T) {
	t.Parallel()
	lf := lockfile.New()

	// Add new package
	lf.AddOrUpdatePackage("libA", "urlA", "pathA", "hashA")
	require.Contains(t, lf.Package, "libA")
	assert.Equal(t, "urlA", lf.Package["libA"].Source)
	assert.Equal(t, "pathA", lf.Package["libA"].Path)
	assert.Equal(t, "hashA", lf.Package["libA"].Hash)

	// Update existing package
	lf.AddOrUpdatePackage("libA", "urlA_updated", "pathA_updated", "hashA_updated")
	require.Contains(t, lf.Package, "libA")
	assert.Equal(t, "urlA_updated", lf.Package["libA"].Source)
	assert.Equal(t, "pathA_updated", lf.Package["libA"].Path)
	assert.Equal(t, "hashA_updated", lf.Package["libA"].Hash)

	// Add another package
	lf.AddOrUpdatePackage("libB", "urlB", "pathB", "hashB")
	require.Contains(t, lf.Package, "libB")
	assert.Equal(t, "urlB", lf.Package["libB"].Source)
	assert.Len(t, lf.Package, 2, "Incorrect number of packages after adding multiple")
}

func TestAddOrUpdatePackage_NilMap(t *testing.T) {
	t.Parallel()
	lf := &lockfile.Lockfile{ApiVersion: "1", Package: nil} // Simulate a scenario where Package map is nil

	lf.AddOrUpdatePackage("libC", "urlC", "pathC", "hashC")
	require.NotNil(t, lf.Package, "Package map should be initialized by AddOrUpdatePackage")
	require.Contains(t, lf.Package, "libC")
	assert.Equal(t, "urlC", lf.Package["libC"].Source)
}
