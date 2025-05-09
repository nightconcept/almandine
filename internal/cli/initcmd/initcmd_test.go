// Package commands_test contains tests for the commands package.
package initcmd

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

// Helper function to simulate user input for prompts
func simulateInput(inputs []string) (*os.File, *os.File, error) {
	r, w, err := os.Pipe()
	if err != nil {
		return nil, nil, err
	}
	// Write all inputs separated by newlines
	inputString := strings.Join(inputs, "\n") + "\n"
	_, err = w.WriteString(inputString)
	if err != nil {
		_ = r.Close()
		_ = w.Close()
		return nil, nil, err
	}
	_ = w.Close() // Close writer to signal EOF for reader
	return r, w, nil
}

// Helper function to capture stdout
func captureOutput() (*os.File, *os.File, *bytes.Buffer, error) {
	r, w, err := os.Pipe()
	if err != nil {
		return nil, nil, nil, err
	}
	var buf bytes.Buffer
	// Use a MultiWriter to capture stdout and also print it if needed for debugging
	_, _ = w.Write([]byte{})
	return r, w, &buf, nil
}

func TestInitCommand(t *testing.T) {
	// --- Test Setup ---
	tempDir, err := os.MkdirTemp("", "almandine_init_test")
	require.NoError(t, err, "Failed to create temporary directory")
	defer func() { _ = os.RemoveAll(tempDir) }() // Clean up afterwards

	originalWd, err := os.Getwd()
	require.NoError(t, err, "Failed to get current working directory")
	err = os.Chdir(tempDir)
	require.NoError(t, err, "Failed to change to temporary directory")
	defer func() { _ = os.Chdir(originalWd) }() // Change back

	// Prepare simulated user input (simulate pressing Enter for defaults where applicable)
	// Order: name, version, license, description, script name, script cmd, empty script name, dep name, dep src, empty dep name
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

	// Redirect Stdin
	oldStdin := os.Stdin
	rStdin, _, err := simulateInput(simulatedInputs)
	require.NoError(t, err, "Failed to simulate stdin")
	os.Stdin = rStdin
	defer func() { os.Stdin = oldStdin; _ = rStdin.Close() }() // Restore Stdin

	// Capture Stdout (optional, but can be useful for debugging output)
	oldStdout := os.Stdout
	rStdout, wStdout, _, err := captureOutput()
	require.NoError(t, err, "Failed to capture stdout")
	os.Stdout = wStdout
	defer func() { os.Stdout = oldStdout; _ = wStdout.Close(); _ = rStdout.Close() }() // Restore Stdout

	// --- Run Command ---
	app := &cli.App{
		Name: "almandine-test",
		Commands: []*cli.Command{
			GetInitCommand(),
		},
	}

	runErr := app.Run([]string{"almandine-test", "init"})

	// --- Assertions ---
	assert.NoError(t, runErr, "Init command returned an error")

	// Check if project.toml was created
	tomlPath := filepath.Join(tempDir, "project.toml")
	_, err = os.Stat(tomlPath)
	require.NoError(t, err, "project.toml was not created")

	// Read and parse the created project.toml
	tomlBytes, err := os.ReadFile(tomlPath)
	require.NoError(t, err, "Failed to read project.toml")

	var generatedConfig project.Project
	err = toml.Unmarshal(tomlBytes, &generatedConfig)
	require.NoError(t, err, "Failed to unmarshal project.toml")

	// Verify Package Metadata
	assert.Equal(t, "test-project", generatedConfig.Package.Name, "Package name mismatch")
	assert.Equal(t, "1.2.3", generatedConfig.Package.Version, "Version mismatch")
	assert.Equal(t, "Apache-2.0", generatedConfig.Package.License, "License mismatch")
	assert.Equal(t, "A test project", generatedConfig.Package.Description, "Description mismatch")

	// Verify Scripts (should include the default 'run' and the provided 'build')
	expectedScripts := map[string]string{
		"run": "lua src/main.lua",
	}
	assert.Equal(t, expectedScripts, generatedConfig.Scripts, "Scripts mismatch")

	// Verify Dependencies
	expectedDependencies := map[string]project.Dependency{
		"my-dep": {
			Source: "github.com/user/repo",
			Path:   "", // Path is initially empty for placeholder dependencies
		},
	}
	assert.Equal(t, expectedDependencies, generatedConfig.Dependencies, "Dependencies mismatch")

	// Optional: Check stdout content if needed (example)
	// stdoutContent := capturedOutput.String()
	// assert.Contains(t, stdoutContent, "Wrote to project.toml", "Expected confirmation message in output")
}

// Test case for empty description and no extra scripts/dependencies (uses defaults)
func TestInitCommand_DefaultsAndEmpty(t *testing.T) {
	// --- Test Setup ---
	tempDir, err := os.MkdirTemp("", "almandine_init_test_defaults")
	require.NoError(t, err, "Failed to create temporary directory")
	defer func() { _ = os.RemoveAll(tempDir) }()

	originalWd, err := os.Getwd()
	require.NoError(t, err, "Failed to get current working directory")
	err = os.Chdir(tempDir)
	require.NoError(t, err, "Failed to change to temporary directory")
	defer func() { _ = os.Chdir(originalWd) }()

	// Simulate pressing Enter for all prompts except name (use default)
	// name, version (default), license (default), description (empty), empty script, empty dep
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

	// --- Run Command ---
	app := &cli.App{
		Name: "almandine-test",
		Commands: []*cli.Command{
			GetInitCommand(),
		},
	}
	runErr := app.Run([]string{"almandine-test", "init"})

	// --- Assertions ---
	assert.NoError(t, runErr, "Init command returned an error")

	tomlPath := filepath.Join(tempDir, "project.toml")
	tomlBytes, err := os.ReadFile(tomlPath)
	require.NoError(t, err, "Failed to read project.toml")

	var generatedConfig project.Project
	err = toml.Unmarshal(tomlBytes, &generatedConfig)
	require.NoError(t, err, "Failed to unmarshal project.toml")

	// Verify Package Metadata (Defaults and empty description)
	assert.Equal(t, "default-proj", generatedConfig.Package.Name, "Package name mismatch")
	assert.Equal(t, "0.1.0", generatedConfig.Package.Version, "Version mismatch (default expected)")
	assert.Equal(t, "MIT", generatedConfig.Package.License, "License mismatch (default expected)")
	assert.Equal(t, "", generatedConfig.Package.Description, "Description should be empty") // Check omitempty worked

	// Verify Scripts (should only include the default 'run')
	expectedScripts := map[string]string{
		"run": "lua src/main.lua",
	}
	assert.Equal(t, expectedScripts, generatedConfig.Scripts, "Scripts mismatch (only default expected)")

	// Verify Dependencies (should be empty or nil)
	assert.Nil(t, generatedConfig.Dependencies, "Dependencies should be nil/omitted") // Or assert.Empty(...) if preferred
}
