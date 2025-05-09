package config

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/nightconcept/almandine/internal/core/project"
)

func TestLoadProjectToml_Valid(t *testing.T) {
	tempDir := t.TempDir()
	validTomlContent := `
[package]
name = "test-project"
version = "0.1.0"
license = "MIT"
description = "A test project"

[scripts]
start = "go run main.go"

[dependencies]
testdep = { source = "github.com/user/repo/file.lua", path = "libs/testdep.lua" }
`
	projectFilePath := filepath.Join(tempDir, ProjectTomlName)
	err := os.WriteFile(projectFilePath, []byte(validTomlContent), 0644)
	require.NoError(t, err)

	proj, err := LoadProjectToml(tempDir)
	require.NoError(t, err)
	require.NotNil(t, proj)

	assert.Equal(t, "test-project", proj.Package.Name)
	assert.Equal(t, "0.1.0", proj.Package.Version)
	assert.Equal(t, "MIT", proj.Package.License)
	assert.Equal(t, "A test project", proj.Package.Description)
	assert.Equal(t, "go run main.go", proj.Scripts["start"])
	assert.NotNil(t, proj.Dependencies["testdep"])
	assert.Equal(t, "github.com/user/repo/file.lua", proj.Dependencies["testdep"].Source)
	assert.Equal(t, "libs/testdep.lua", proj.Dependencies["testdep"].Path)
}

func TestLoadProjectToml_NotFound(t *testing.T) {
	tempDir := t.TempDir()
	_, err := LoadProjectToml(tempDir)
	assert.Error(t, err)
	assert.True(t, os.IsNotExist(err), "Error should be a 'file not found' type error")
}

func TestLoadProjectToml_InvalidFormat(t *testing.T) {
	tempDir := t.TempDir()
	invalidTomlContent := `
[package
name = "test-project"
version = "0.1.0"
`
	projectFilePath := filepath.Join(tempDir, ProjectTomlName)
	err := os.WriteFile(projectFilePath, []byte(invalidTomlContent), 0644)
	require.NoError(t, err)

	_, err = LoadProjectToml(tempDir)
	assert.Error(t, err)
	// We can't easily assert the exact TOML parsing error type here without more specific error handling in the main code,
	// but we expect an error.
}

func TestWriteProjectToml_NewFile(t *testing.T) {
	tempDir := t.TempDir()
	projData := &project.Project{
		Package: &project.PackageInfo{
			Name:        "new-project",
			Version:     "1.0.0",
			License:     "Apache-2.0",
			Description: "A brand new project",
		},
		Scripts: map[string]string{
			"build": "go build .",
		},
		Dependencies: map[string]project.Dependency{
			"dep1": {Source: "github.com/org/dep1/mod.lua", Path: "vendor/dep1.lua"},
		},
	}

	err := WriteProjectToml(tempDir, projData)
	require.NoError(t, err)

	// Verify by loading it back
	loadedProj, err := LoadProjectToml(tempDir)
	require.NoError(t, err)
	require.NotNil(t, loadedProj)

	assert.Equal(t, "new-project", loadedProj.Package.Name)
	assert.Equal(t, "1.0.0", loadedProj.Package.Version)
	assert.Equal(t, "Apache-2.0", loadedProj.Package.License)
	assert.Equal(t, "A brand new project", loadedProj.Package.Description)
	assert.Equal(t, "go build .", loadedProj.Scripts["build"])
	assert.NotNil(t, loadedProj.Dependencies["dep1"])
	assert.Equal(t, "github.com/org/dep1/mod.lua", loadedProj.Dependencies["dep1"].Source)
	assert.Equal(t, "vendor/dep1.lua", loadedProj.Dependencies["dep1"].Path)
}

func TestWriteProjectToml_OverwriteFile(t *testing.T) {
	tempDir := t.TempDir()
	initialTomlContent := `
[package]
name = "old-project"
version = "0.0.1"
`
	projectFilePath := filepath.Join(tempDir, ProjectTomlName)
	err := os.WriteFile(projectFilePath, []byte(initialTomlContent), 0644)
	require.NoError(t, err)

	projData := &project.Project{
		Package: &project.PackageInfo{
			Name:    "updated-project",
			Version: "2.0.0",
		},
	}

	err = WriteProjectToml(tempDir, projData)
	require.NoError(t, err)

	loadedProj, err := LoadProjectToml(tempDir)
	require.NoError(t, err)
	require.NotNil(t, loadedProj)

	assert.Equal(t, "updated-project", loadedProj.Package.Name)
	assert.Equal(t, "2.0.0", loadedProj.Package.Version)
	assert.Nil(t, loadedProj.Scripts)      // Ensure old fields are gone
	assert.Nil(t, loadedProj.Dependencies) // Ensure old fields are gone
}
