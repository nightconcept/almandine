// Package add provides the 'add' command implementation for the Almandine CLI.
// Tests in this file verify the dependency addition behavior across various scenarios:
// - GitHub repository integration with version tags and commit hashes
// - Error handling for missing files, download failures, and write permissions
// - File management including cleanup on partial failures
package add

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/BurntSushi/toml"
	"github.com/nightconcept/almandine/internal/core/config"
	"github.com/nightconcept/almandine/internal/core/lockfile"
	"github.com/nightconcept/almandine/internal/core/project"
	"github.com/nightconcept/almandine/internal/core/source"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/urfave/cli/v2"
)

// SetTestModeBypassHostValidation enables mock server testing without GitHub host validation.
// This is needed because the test mock server uses http:// instead of https://, which would
// normally be rejected by the GitHub client's host validation.
func init() {
	source.SetTestModeBypassHostValidation(true)
}

// setupAddTestEnvironment creates an isolated test environment with a project.toml.
// It returns the path to a temporary directory that will be automatically cleaned up
// after the test completes. The initialProjectTomlContent parameter allows tests to
// start with a specific project configuration.
func setupAddTestEnvironment(t *testing.T, initialProjectTomlContent string) (tempDir string) {
	t.Helper()
	tempDir = t.TempDir()

	if initialProjectTomlContent != "" {
		projectTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
		err := os.WriteFile(projectTomlPath, []byte(initialProjectTomlContent), 0644)
		require.NoError(t, err, "Failed to write initial project.toml")
	}
	return tempDir
}

// runAddCommand executes the 'add' command in a specific working directory.
// It temporarily changes the working directory and suppresses the CLI's default
// exit behavior to allow test assertions on command failures.
func runAddCommand(t *testing.T, workDir string, addCmdArgs ...string) error {
	t.Helper()

	originalWd, err := os.Getwd()
	require.NoError(t, err, "Failed to get current working directory")
	err = os.Chdir(workDir)
	require.NoError(t, err, "Failed to change to working directory: %s", workDir)
	defer func() {
		require.NoError(t, os.Chdir(originalWd), "Failed to restore original working directory")
	}()

	app := &cli.App{
		Name: "almd-test-add",
		Commands: []*cli.Command{
			AddCmd(),
		},
		// Suppress help printer during tests unless specifically testing help output
		Writer:    os.Stderr, // Default, or io.Discard for cleaner test logs
		ErrWriter: os.Stderr, // Default, or io.Discard
		ExitErrHandler: func(context *cli.Context, err error) {
			// Do nothing by default, let the test assertions handle errors from app.Run()
			// This prevents os.Exit(1) from urfave/cli from stopping the test run
		},
	}

	cliArgs := []string{"almd-test-add", "add"}
	cliArgs = append(cliArgs, addCmdArgs...)

	return app.Run(cliArgs)
}

// startMockServer creates a test HTTP server that simulates GitHub's API and raw content
// responses. It takes a map of paths to their corresponding responses, allowing tests to
// simulate both successful and error scenarios for API calls and file downloads.
func startMockServer(t *testing.T, pathResponses map[string]struct {
	Body string
	Code int
}) *httptest.Server {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Construct path with query for matching, as GitHub API calls include queries.
		requestPathWithQuery := r.URL.Path
		if r.URL.RawQuery != "" {
			requestPathWithQuery += "?" + r.URL.RawQuery
		}

		for path, response := range pathResponses {
			// Allow simple path match or path with query match
			if r.Method == http.MethodGet && (r.URL.Path == path || requestPathWithQuery == path) {
				w.WriteHeader(response.Code)
				_, err := w.Write([]byte(response.Body))
				assert.NoError(t, err, "Mock server failed to write response body for path: %s", path)
				return
			}
		}
		t.Logf("Mock server: unexpected request: Method %s, Path %s, Query %s", r.Method, r.URL.Path, r.URL.RawQuery)
		http.NotFound(w, r)
	}))
	t.Cleanup(server.Close) // Ensure server is closed after the test
	return server
}

// readProjectToml parses and validates the project configuration files. They ensure the
// files are properly formatted and contain the expected content after command execution.
func readProjectToml(t *testing.T, tomlPath string) project.Project {
	t.Helper()
	bytes, err := os.ReadFile(tomlPath)
	require.NoError(t, err, "Failed to read project.toml: %s", tomlPath)

	var projCfg project.Project
	err = toml.Unmarshal(bytes, &projCfg)
	require.NoError(t, err, "Failed to unmarshal project.toml: %s", tomlPath)
	return projCfg
}

// readAlmdLockToml parses and validates the project configuration files. They ensure the
// files are properly formatted and contain the expected content after command execution.
func readAlmdLockToml(t *testing.T, lockPath string) project.LockFile {
	t.Helper()
	bytes, err := os.ReadFile(lockPath)
	require.NoError(t, err, "Failed to read almd-lock.toml: %s", lockPath)

	var lockCfg project.LockFile
	err = toml.Unmarshal(bytes, &lockCfg)
	require.NoError(t, err, "Failed to unmarshal almd-lock.toml: %s", lockPath)
	return lockCfg
}

// TestAddCommand_Success_ExplicitNameAndDir verifies the happy path for adding a
// dependency with explicit name (-n) and directory (-d) flags. This represents the
// most common usage pattern where users want control over dependency placement.
func TestAddCommand_Success_ExplicitNameAndDir(t *testing.T) {
	initialTomlContent := `
[package]
name = "test-project"
version = "0.1.0"
`
	tempDir := setupAddTestEnvironment(t, initialTomlContent)

	mockContent := "// This is a mock lua library content\nlocal lib = {}\nfunction lib.hello() print('hello from lua lib') end\nreturn lib\n"
	mockFileURLPath := "/testowner/testrepo/v1.0.0/mylib_script.lua"
	mockCommitSHA := "fixedmockshaforexplicittest1234567890"
	mockAPIPathForCommits := fmt.Sprintf("/repos/%s/%s/commits?path=%s&sha=%s&per_page=1", "testowner", "testrepo", "mylib_script.lua", "v1.0.0")
	mockAPIResponseBody := fmt.Sprintf(`[{"sha": "%s"}]`, mockCommitSHA)

	pathResps := map[string]struct {
		Body string
		Code int
	}{
		mockFileURLPath:       {Body: mockContent, Code: http.StatusOK},
		mockAPIPathForCommits: {Body: mockAPIResponseBody, Code: http.StatusOK},
	}
	mockServer := startMockServer(t, pathResps)

	originalGHAPIBaseURL := source.GithubAPIBaseURL
	source.GithubAPIBaseURL = mockServer.URL
	defer func() { source.GithubAPIBaseURL = originalGHAPIBaseURL }()

	dependencyURL := mockServer.URL + mockFileURLPath
	dependencyName := "mylib"
	dependencyDir := "vendor/custom"

	err := runAddCommand(t, tempDir,
		"-n", dependencyName,
		"-d", dependencyDir,
		dependencyURL,
	)
	require.NoError(t, err, "almd add command failed")

	extractedSourceFileExtension := filepath.Ext(mockFileURLPath)
	expectedFileNameOnDisk := dependencyName + extractedSourceFileExtension

	downloadedFilePath := filepath.Join(tempDir, dependencyDir, expectedFileNameOnDisk)
	require.FileExists(t, downloadedFilePath, "Downloaded file does not exist at expected path: %s", downloadedFilePath)

	contentBytes, readErr := os.ReadFile(downloadedFilePath)
	require.NoError(t, readErr, "Failed to read downloaded file: %s", downloadedFilePath)
	assert.Equal(t, mockContent, string(contentBytes), "Downloaded file content mismatch")

	projectTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	projCfg := readProjectToml(t, projectTomlPath)

	require.NotNil(t, projCfg.Dependencies, "Dependencies map in project.toml is nil")
	depEntry, ok := projCfg.Dependencies[dependencyName]
	require.True(t, ok, "Dependency entry not found in project.toml for: %s", dependencyName)

	expectedCanonicalSource := "github:testowner/testrepo/mylib_script.lua@v1.0.0"
	assert.Equal(t, expectedCanonicalSource, depEntry.Source, "Dependency source mismatch in project.toml")
	assert.Equal(t, filepath.ToSlash(filepath.Join(dependencyDir, expectedFileNameOnDisk)), depEntry.Path, "Dependency path mismatch in project.toml")

	lockFilePath := filepath.Join(tempDir, "almd-lock.toml")
	require.FileExists(t, lockFilePath, "almd-lock.toml was not created")
	lockCfg := readAlmdLockToml(t, lockFilePath)

	assert.Equal(t, "1", lockCfg.APIVersion, "API version in almd-lock.toml mismatch")
	require.NotNil(t, lockCfg.Package, "Packages map in almd-lock.toml is nil")
	lockPkgEntry, ok := lockCfg.Package[dependencyName]
	require.True(t, ok, "Package entry not found in almd-lock.toml for: %s", dependencyName)

	assert.Equal(t, dependencyURL, lockPkgEntry.Source, "Package source mismatch in almd-lock.toml (raw URL)")
	assert.Equal(t, filepath.ToSlash(filepath.Join(dependencyDir, expectedFileNameOnDisk)), lockPkgEntry.Path, "Package path mismatch in almd-lock.toml")

	expectedHash := "commit:" + mockCommitSHA
	assert.Equal(t, expectedHash, lockPkgEntry.Hash, "Package hash mismatch in almd-lock.toml")
}

// TestAddCommand_Success_InferredName_DefaultDir verifies that dependencies can be
// added without explicit naming, testing the package's name inference logic and
// default directory placement when no -d flag is provided.
func TestAddCommand_Success_InferredName_DefaultDir(t *testing.T) {
	initialTomlContent := `
[package]
name = "test-project-inferred"
version = "0.1.0"
`
	tempDir := setupAddTestEnvironment(t, initialTomlContent)

	mockContent := "// This is a mock lua library for inferred name test\nlocal lib = {}\nreturn lib\n"
	mockFileURLPath_Inferred := "/inferredowner/inferredrepo/mainbranch/test_dependency_file.lua"
	mockCommitSHA_Inferred := "fixedmockshaforinferredtest1234567890"
	mockAPIPathForCommits_Inferred := fmt.Sprintf("/repos/%s/%s/commits?path=%s&sha=%s&per_page=1", "inferredowner", "inferredrepo", "test_dependency_file.lua", "mainbranch")
	mockAPIResponseBody_Inferred := fmt.Sprintf(`[{"sha": "%s"}]`, mockCommitSHA_Inferred)

	pathResps_Inferred := map[string]struct {
		Body string
		Code int
	}{
		mockFileURLPath_Inferred:       {Body: mockContent, Code: http.StatusOK},
		mockAPIPathForCommits_Inferred: {Body: mockAPIResponseBody_Inferred, Code: http.StatusOK},
	}
	mockServer := startMockServer(t, pathResps_Inferred)

	originalGHAPIBaseURL_Inferred := source.GithubAPIBaseURL
	source.GithubAPIBaseURL = mockServer.URL
	defer func() { source.GithubAPIBaseURL = originalGHAPIBaseURL_Inferred }()

	dependencyURL := mockServer.URL + mockFileURLPath_Inferred

	err := runAddCommand(t, tempDir, dependencyURL)
	require.NoError(t, err, "almd add command failed")

	sourceFileName := filepath.Base(mockFileURLPath_Inferred)
	inferredDepName := strings.TrimSuffix(sourceFileName, filepath.Ext(sourceFileName))

	expectedDiskFileName := sourceFileName
	expectedDirOnDisk := "src/lib"
	downloadedFilePath := filepath.Join(tempDir, expectedDirOnDisk, expectedDiskFileName)

	require.FileExists(t, downloadedFilePath, "Downloaded file does not exist at expected path: %s", downloadedFilePath)
	contentBytes, readErr := os.ReadFile(downloadedFilePath)
	require.NoError(t, readErr, "Failed to read downloaded file: %s", downloadedFilePath)
	assert.Equal(t, mockContent, string(contentBytes), "Downloaded file content mismatch")

	projectTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	projCfg := readProjectToml(t, projectTomlPath)

	require.NotNil(t, projCfg.Dependencies, "Dependencies map in project.toml is nil")
	depEntry, ok := projCfg.Dependencies[inferredDepName]
	require.True(t, ok, "Dependency entry not found in project.toml for inferred name: %s", inferredDepName)

	expectedCanonicalSource := "github:inferredowner/inferredrepo/test_dependency_file.lua@mainbranch"
	assert.Equal(t, expectedCanonicalSource, depEntry.Source, "Dependency source mismatch in project.toml")

	expectedPathInToml := filepath.ToSlash(filepath.Join(expectedDirOnDisk, expectedDiskFileName))
	assert.Equal(t, expectedPathInToml, depEntry.Path, "Dependency path mismatch in project.toml")

	lockFilePath := filepath.Join(tempDir, "almd-lock.toml")
	require.FileExists(t, lockFilePath, "almd-lock.toml was not created")
	lockCfg := readAlmdLockToml(t, lockFilePath)

	assert.Equal(t, "1", lockCfg.APIVersion, "API version in almd-lock.toml mismatch")
	require.NotNil(t, lockCfg.Package, "Packages map in almd-lock.toml is nil")
	lockPkgEntry, ok := lockCfg.Package[inferredDepName]
	require.True(t, ok, "Package entry not found in almd-lock.toml for inferred name: %s", inferredDepName)

	assert.Equal(t, dependencyURL, lockPkgEntry.Source, "Package source mismatch in almd-lock.toml (raw URL)")
	assert.Equal(t, expectedPathInToml, lockPkgEntry.Path, "Package path mismatch in almd-lock.toml")

	expectedHash := "commit:" + mockCommitSHA_Inferred
	assert.Equal(t, expectedHash, lockPkgEntry.Hash, "Package hash mismatch in almd-lock.toml")
}

// TestAddCommand_GithubURLWithCommitHash verifies handling of GitHub URLs that
// specify exact commit hashes instead of tags/branches. This is important for
// users who need to pin dependencies to specific commits for reproducibility.
func TestAddCommand_GithubURLWithCommitHash(t *testing.T) {
	initialTomlContent := `
[package]
name = "test-project-commit-hash"
version = "0.1.0"
`
	tempDir := setupAddTestEnvironment(t, initialTomlContent)

	mockContent := "// Mock Lib with specific commit\nlocal lib = { info = \"version_commit123\" }\nreturn lib\n"
	directCommitSHA := "commitabc123def456ghi789jkl012mno345pqr"
	mockFileURLPath := fmt.Sprintf("/ghowner/ghrepo/%s/mylib.lua", directCommitSHA)

	pathResps := map[string]struct {
		Body string
		Code int
	}{
		mockFileURLPath: {Body: mockContent, Code: http.StatusOK},
	}
	mockAPIPathForCommits := fmt.Sprintf("/repos/ghowner/ghrepo/commits?path=mylib.lua&sha=%s&per_page=1", directCommitSHA)
	pathResps[mockAPIPathForCommits] = struct {
		Body string
		Code int
	}{
		Body: fmt.Sprintf(`[{"sha": "%s"}]`, directCommitSHA),
		Code: http.StatusOK,
	}
	mockServer := startMockServer(t, pathResps)

	originalGHAPIBaseURL := source.GithubAPIBaseURL
	source.GithubAPIBaseURL = mockServer.URL

	defer func() {
		source.GithubAPIBaseURL = originalGHAPIBaseURL
	}()

	dependencyURL := mockServer.URL + mockFileURLPath

	dependencyName := "mylibcommit"
	dependencyDir := "libs/gh"

	err := runAddCommand(t, tempDir,
		"-n", dependencyName,
		"-d", dependencyDir,
		dependencyURL,
	)
	require.NoError(t, err, "almd add command failed for GitHub URL with commit hash")

	expectedFileNameOnDisk := dependencyName + ".lua"
	downloadedFilePath := filepath.Join(tempDir, dependencyDir, expectedFileNameOnDisk)

	require.FileExists(t, downloadedFilePath)
	contentBytes, _ := os.ReadFile(downloadedFilePath)
	assert.Equal(t, mockContent, string(contentBytes))

	projectTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	projCfg := readProjectToml(t, projectTomlPath)
	depEntry, ok := projCfg.Dependencies[dependencyName]
	require.True(t, ok, "Dependency entry not found in project.toml")

	expectedCanonicalSource := fmt.Sprintf("github:ghowner/ghrepo/mylib.lua@%s", directCommitSHA)
	assert.Equal(t, expectedCanonicalSource, depEntry.Source)
	assert.Equal(t, filepath.ToSlash(filepath.Join(dependencyDir, expectedFileNameOnDisk)), depEntry.Path)

	lockFilePath := filepath.Join(tempDir, "almd-lock.toml")
	require.FileExists(t, lockFilePath)
	lockCfg := readAlmdLockToml(t, lockFilePath)
	lockPkgEntry, ok := lockCfg.Package[dependencyName]
	require.True(t, ok, "Package entry not found in almd-lock.toml")

	assert.Equal(t, dependencyURL, lockPkgEntry.Source)
	assert.Equal(t, filepath.ToSlash(filepath.Join(dependencyDir, expectedFileNameOnDisk)), lockPkgEntry.Path)

	expectedHashWithCommit := "commit:" + directCommitSHA
	assert.Equal(t, expectedHashWithCommit, lockPkgEntry.Hash, "Package hash mismatch in almd-lock.toml (direct commit hash)")
}

// TestAddCommand_DownloadFailure verifies proper error handling and cleanup when
// a dependency download fails. The test ensures no partial state is left behind
// in the project configuration or filesystem.
func TestAddCommand_DownloadFailure(t *testing.T) {
	initialTomlContent := `
[package]
name = "test-project-dlfail"
version = "0.1.0"
`
	tempDir := setupAddTestEnvironment(t, initialTomlContent)

	mockFileURLPath := "/owner/repo/main/nonexistent.lua"
	pathResps := map[string]struct {
		Body string
		Code int
	}{
		mockFileURLPath: {Body: "File not found", Code: http.StatusNotFound},
	}
	mockServer := startMockServer(t, pathResps)
	dependencyURL := mockServer.URL + mockFileURLPath

	err := runAddCommand(t, tempDir, dependencyURL)

	require.Error(t, err, "almd add command should return an error on download failure")

	if exitErr, ok := err.(cli.ExitCoder); ok {
		assert.Contains(t, exitErr.Error(), "Error downloading file", "Error message should indicate download failure")
		assert.Contains(t, exitErr.Error(), "status code 404", "Error message should indicate 404 status")
	} else {
		assert.Fail(t, "Expected cli.ExitError for command failure")
	}

	expectedFilePath := filepath.Join(tempDir, "src/lib/nonexistent.lua")
	_, statErr := os.Stat(expectedFilePath)
	assert.True(t, os.IsNotExist(statErr), "Dependency file should not have been created on download failure")

	projectTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	projCfg := readProjectToml(t, projectTomlPath)
	assert.Equal(t, "test-project-dlfail", projCfg.Package.Name, "project.toml package name should be unchanged")
	assert.Len(t, projCfg.Dependencies, 0, "project.toml should have no dependencies after a failed add")

	lockFilePath := filepath.Join(tempDir, "almd-lock.toml")
	_, statErrLock := os.Stat(lockFilePath)
	assert.True(t, os.IsNotExist(statErrLock), "almd-lock.toml should not have been created on download failure")
}

// TestAddCommand_ProjectTomlNotFound verifies the error handling when attempting
// to add a dependency to a project without a project.toml file. This protects
// against accidental dependency additions outside of Almandine projects.
func TestAddCommand_ProjectTomlNotFound(t *testing.T) {
	tempDir := setupAddTestEnvironment(t, "")

	mockContent := "// Some content"
	mockFileURLPath := "/owner/repo/main/somefile.lua"
	pathResps := map[string]struct {
		Body string
		Code int
	}{
		mockFileURLPath: {Body: mockContent, Code: http.StatusOK},
	}
	mockServer := startMockServer(t, pathResps)
	dependencyURL := mockServer.URL + mockFileURLPath

	err := runAddCommand(t, tempDir, dependencyURL)

	require.Error(t, err, "almd add command should return an error when project.toml is not found")

	if exitErr, ok := err.(cli.ExitCoder); ok {
		assert.Contains(t, exitErr.Error(), "project.toml", "Error message should indicate project.toml was not found or could not be loaded")
		assert.Contains(t, exitErr.Error(), "no such file or directory", "Error message details should reflect os.IsNotExist")
	} else {
		assert.Fail(t, "Expected a cli.ExitError if command was to fail as per task requirements")
	}

	expectedFilePath := filepath.Join(tempDir, "src/lib/somefile.lua")
	_, statErr := os.Stat(expectedFilePath)
	assert.True(t, os.IsNotExist(statErr), "Dependency file should not have been created if project.toml is missing and command errored")

	lockFilePath := filepath.Join(tempDir, "almd-lock.toml")
	_, statErrLock := os.Stat(lockFilePath)
	assert.True(t, os.IsNotExist(statErrLock), "almd-lock.toml should not have been created if project.toml is missing and command errored")

	projectTomlPathMain := filepath.Join(tempDir, config.ProjectTomlName)
	_, statErrProject := os.Stat(projectTomlPathMain)
	assert.True(t, os.IsNotExist(statErrProject), "project.toml should not have been created by the add command if it was missing and an error was expected")
}

// TestAddCommand_CleanupOnFailure_LockfileWriteError verifies that the command
// properly cleans up any downloaded files and maintains project.toml consistency
// when it fails to write the lockfile. This is crucial for preventing partial
// or inconsistent project states that could break dependency management.
func TestAddCommand_CleanupOnFailure_LockfileWriteError(t *testing.T) {
	initialTomlContent := `
[package]
name = "test-cleanup-project"
version = "0.1.0"
`
	tempDir := setupAddTestEnvironment(t, initialTomlContent)
	projectTomlPath := filepath.Join(tempDir, config.ProjectTomlName)

	mockContent := "// Mock library content for cleanup test\\nlocal m = {}\\nfunction m.do() return 'ok' end\\nreturn m"

	mockOwner := "testowner"
	mockRepo := "testrepo"
	mockRef := "main"
	mockFileName := "mocklib.lua"
	mockFileURLPath := fmt.Sprintf("/%s/%s/%s/%s", mockOwner, mockRepo, mockRef, mockFileName)

	mockCommitSHA := "mockcleanupcommitsha1234567890"
	mockAPIPathForCommits := fmt.Sprintf("/repos/%s/%s/commits?path=%s&sha=%s&per_page=1", mockOwner, mockRepo, mockFileName, mockRef)
	mockAPIResponseBody := fmt.Sprintf(`[{"sha": "%s"}]`, mockCommitSHA)

	pathResps := map[string]struct {
		Body string
		Code int
	}{
		mockFileURLPath:       {Body: mockContent, Code: http.StatusOK},
		mockAPIPathForCommits: {Body: mockAPIResponseBody, Code: http.StatusOK},
	}
	mockServer := startMockServer(t, pathResps)

	originalGHAPIBaseURL := source.GithubAPIBaseURL
	source.GithubAPIBaseURL = mockServer.URL
	defer func() { source.GithubAPIBaseURL = originalGHAPIBaseURL }()

	dependencyURL := mockServer.URL + mockFileURLPath

	sourceFileName := mockFileName
	expectedDepName := strings.TrimSuffix(sourceFileName, filepath.Ext(sourceFileName))
	defaultLibsDir := "src/lib"
	expectedDownloadedFilePath := filepath.Join(tempDir, defaultLibsDir, sourceFileName)

	lockFilePath := filepath.Join(tempDir, lockfile.LockfileName)
	err := os.Mkdir(lockFilePath, 0755)
	require.NoError(t, err, "Test setup: Failed to create %s as a directory", lockfile.LockfileName)

	cmdErr := runAddCommand(t, tempDir, dependencyURL)

	require.Error(t, cmdErr, "almd add command should return an error due to lockfile write failure")

	if exitErr, ok := cmdErr.(cli.ExitCoder); ok {
		errorOutput := strings.ToLower(exitErr.Error())
		assert.Contains(t, errorOutput, "lockfile", "Error message should mention 'lockfile'")
		assert.Contains(t, errorOutput, lockfile.LockfileName, "Error message should mention the lockfile name")
		assert.Condition(t, func() bool {
			return strings.Contains(errorOutput, "is a directory") ||
				strings.Contains(errorOutput, "toml") ||
				strings.Contains(errorOutput, "permission denied")
		}, "Error message details should indicate a write/type issue with the lockfile path: %s", errorOutput)
	} else {
		lowerCmdErr := strings.ToLower(cmdErr.Error())
		assert.Contains(t, lowerCmdErr, "lockfile", "Direct error message should mention 'lockfile': %v", cmdErr)
		assert.Fail(t, "Expected command error to be a cli.ExitCoder, got %T: %v", cmdErr, cmdErr)
	}

	_, statErr := os.Stat(expectedDownloadedFilePath)
	assert.True(t, os.IsNotExist(statErr),
		"Downloaded dependency file '%s' should have been removed after lockfile write failure.", expectedDownloadedFilePath)

	projCfg := readProjectToml(t, projectTomlPath)
	depEntry, ok := projCfg.Dependencies[expectedDepName]
	require.True(t, ok, "Dependency '%s' should still be listed in project.toml. Current dependencies: %v", expectedDepName, projCfg.Dependencies)

	expectedCanonicalSource := fmt.Sprintf("github:%s/%s/%s@%s", mockOwner, mockRepo, mockFileName, mockRef)
	assert.Equal(t, expectedCanonicalSource, depEntry.Source, "Dependency source in project.toml for '%s' is incorrect", expectedDepName)
	assert.Equal(t, filepath.ToSlash(filepath.Join(defaultLibsDir, sourceFileName)), depEntry.Path,
		"Dependency path in project.toml is incorrect for '%s'", expectedDepName)

	lockFileStat, statLockErr := os.Stat(lockFilePath)
	require.NoError(t, statLockErr, "Should be able to stat the %s path (which is a directory)", lockfile.LockfileName)
	assert.True(t, lockFileStat.IsDir(), "%s should remain a directory", lockfile.LockfileName)

	_, err = os.ReadFile(lockFilePath)
	require.Error(t, err, "Attempting to read %s (which is a dir) as a file should fail", lockfile.LockfileName)
}
