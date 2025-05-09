// Package init provides functionality for initializing new Almandine projects.
// Tests in this package verify the project initialization behavior and configuration generation.
package init

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/BurntSushi/toml"
	"github.com/nightconcept/almandine/internal/core/project"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/urfave/cli/v2"
)

// simulateInput creates a pipe and writes the given inputs to simulate user input for prompts.
func simulateInput(inputs []string) (*os.File, *os.File, error) {
	r, w, err := os.Pipe()
	if err != nil {
		return nil, nil, err
	}
	inputString := strings.Join(inputs, "\n") + "\n"
	_, err = w.WriteString(inputString)
	if err != nil {
		_ = r.Close()
		_ = w.Close()
		return nil, nil, err
	}
	_ = w.Close()
	return r, w, nil
}

// captureOutput creates a pipe and buffer to capture stdout for testing.
func captureOutput() (*os.File, *os.File, *bytes.Buffer, error) {
	r, w, err := os.Pipe()
	if err != nil {
		return nil, nil, nil, err
	}
	var buf bytes.Buffer
	_, _ = w.Write([]byte{})
	return r, w, &buf, nil
}

// TestInitCommand verifies that the init command correctly handles custom user inputs
// and generates a valid project configuration with specified values. This test ensures
// the interactive prompts work and the resulting TOML file contains the expected content.
func TestInitCommand(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "almandine_init_test")
	require.NoError(t, err, "Failed to create temporary directory")
	defer func() { _ = os.RemoveAll(tempDir) }()

	originalWd, err := os.Getwd()
	require.NoError(t, err, "Failed to get current working directory")
	err = os.Chdir(tempDir)
	require.NoError(t, err, "Failed to change to temporary directory")
	defer func() { _ = os.Chdir(originalWd) }()

	simulatedInputs := []string{
		"test-project",         // Package name
		"1.2.3",                // Version
		"Apache-2.0",           // License
		"A test project",       // Description
		"",                     // Empty script name (finish scripts)
		"my-dep",               // Dependency name 1
		"github.com/user/repo", // Dependency source 1
		"",                     // Empty dependency name (finish dependencies)
	}

	oldStdin := os.Stdin
	rStdin, _, err := simulateInput(simulatedInputs)
	require.NoError(t, err, "Failed to simulate stdin")
	os.Stdin = rStdin
	defer func() { os.Stdin = oldStdin; _ = rStdin.Close() }()

	oldStdout := os.Stdout
	rStdout, wStdout, _, err := captureOutput()
	require.NoError(t, err, "Failed to capture stdout")
	os.Stdout = wStdout
	defer func() { os.Stdout = oldStdout; _ = wStdout.Close(); _ = rStdout.Close() }()

	app := &cli.App{
		Name: "almandine-test",
		Commands: []*cli.Command{
			InitCmd(),
		},
	}

	runErr := app.Run([]string{"almandine-test", "init"})

	assert.NoError(t, runErr, "Init command returned an error")

	tomlPath := filepath.Join(tempDir, "project.toml")
	_, err = os.Stat(tomlPath)
	require.NoError(t, err, "project.toml was not created")

	tomlBytes, err := os.ReadFile(tomlPath)
	require.NoError(t, err, "Failed to read project.toml")

	var generatedConfig project.Project
	err = toml.Unmarshal(tomlBytes, &generatedConfig)
	require.NoError(t, err, "Failed to unmarshal project.toml")

	assert.Equal(t, "test-project", generatedConfig.Package.Name, "Package name mismatch")
	assert.Equal(t, "1.2.3", generatedConfig.Package.Version, "Version mismatch")
	assert.Equal(t, "Apache-2.0", generatedConfig.Package.License, "License mismatch")
	assert.Equal(t, "A test project", generatedConfig.Package.Description, "Description mismatch")

	expectedScripts := map[string]string{
		"run": "lua src/main.lua",
	}
	assert.Equal(t, expectedScripts, generatedConfig.Scripts, "Scripts mismatch")
}

// TestInitCommand_DefaultsAndEmpty verifies that the init command properly handles
// default values and empty inputs. This ensures the command maintains backward
// compatibility and provides sensible defaults when users skip optional inputs.
func TestInitCommand_DefaultsAndEmpty(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "almandine_init_test_defaults")
	require.NoError(t, err, "Failed to create temporary directory")
	defer func() { _ = os.RemoveAll(tempDir) }()

	originalWd, err := os.Getwd()
	require.NoError(t, err, "Failed to get current working directory")
	err = os.Chdir(tempDir)
	require.NoError(t, err, "Failed to change to temporary directory")
	defer func() { _ = os.Chdir(originalWd) }()

	simulatedInputs := []string{
		"default-proj", // Package name
		"",             // Version (use default)
		"",             // License (use default)
		"",             // Description (empty)
		"",             // Empty script name (finish scripts)
		"",             // Empty dependency name (finish dependencies)
	}

	oldStdin := os.Stdin
	rStdin, _, err := simulateInput(simulatedInputs)
	require.NoError(t, err, "Failed to simulate stdin")
	os.Stdin = rStdin
	defer func() { os.Stdin = oldStdin; _ = rStdin.Close() }()

	oldStdout := os.Stdout
	rStdout, wStdout, _, err := captureOutput()
	require.NoError(t, err, "Failed to capture stdout")
	os.Stdout = wStdout
	defer func() { os.Stdout = oldStdout; _ = wStdout.Close(); _ = rStdout.Close() }()

	app := &cli.App{
		Name: "almandine-test",
		Commands: []*cli.Command{
			InitCmd(),
		},
	}
	runErr := app.Run([]string{"almandine-test", "init"})

	assert.NoError(t, runErr, "Init command returned an error")

	tomlPath := filepath.Join(tempDir, "project.toml")
	tomlBytes, err := os.ReadFile(tomlPath)
	require.NoError(t, err, "Failed to read project.toml")

	var generatedConfig project.Project
	err = toml.Unmarshal(tomlBytes, &generatedConfig)
	require.NoError(t, err, "Failed to unmarshal project.toml")

	assert.Equal(t, "default-proj", generatedConfig.Package.Name, "Package name mismatch")
	assert.Equal(t, "0.1.0", generatedConfig.Package.Version, "Version mismatch (default expected)")
	assert.Equal(t, "MIT", generatedConfig.Package.License, "License mismatch (default expected)")
	assert.Equal(t, "", generatedConfig.Package.Description, "Description should be empty")

	expectedScripts := map[string]string{
		"run": "lua src/main.lua",
	}
	assert.Equal(t, expectedScripts, generatedConfig.Scripts, "Scripts mismatch (only default expected)")

	assert.Nil(t, generatedConfig.Dependencies, "Dependencies should be nil/omitted")
}
