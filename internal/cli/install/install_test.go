// Package install_test contains tests for the 'install' command, focusing on dependency
// resolution, download handling, and error scenarios. These tests use mock HTTP servers
// to simulate GitHub API and raw content responses.
package install_test

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/BurntSushi/toml"
	installcmd "github.com/nightconcept/almandine/internal/cli/install"
	"github.com/nightconcept/almandine/internal/core/config"
	"github.com/nightconcept/almandine/internal/core/lockfile"
	"github.com/nightconcept/almandine/internal/core/project"
	"github.com/nightconcept/almandine/internal/core/source"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/urfave/cli/v2"
)

func init() {
	// Enable host validation bypass for testing with mock server
	source.SetTestModeBypassHostValidation(true)
}

// startMockHTTPServer creates an HTTP test server that serves predefined responses for
// specific paths, simulating GitHub's API and raw content servers. Other paths return 404.
// This allows testing various GitHub API response scenarios without network access.
func startMockHTTPServer(t *testing.T, pathResponses map[string]struct {
	Body string
	Code int
}) *httptest.Server {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestPathWithQuery := r.URL.Path
		if r.URL.RawQuery != "" {
			requestPathWithQuery += "?" + r.URL.RawQuery
		}

		for path, response := range pathResponses {
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
	t.Cleanup(server.Close)
	return server
}

// setupInstallTestEnvironment prepares a test environment with configurable project files.
// It creates a temporary directory and initializes it with the provided project.toml,
// almd-lock.toml, and mock dependency files, simulating various project states.
func setupInstallTestEnvironment(t *testing.T, initialProjectTomlContent string, initialLockfileContent string, mockDepFiles map[string]string) (tempDir string) {
	t.Helper()
	tempDir = t.TempDir()

	if initialProjectTomlContent != "" {
		projectTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
		err := os.WriteFile(projectTomlPath, []byte(initialProjectTomlContent), 0644)
		require.NoError(t, err, "Failed to write initial project.toml")
	}

	if initialLockfileContent != "" {
		lockfilePath := filepath.Join(tempDir, lockfile.LockfileName)
		err := os.WriteFile(lockfilePath, []byte(initialLockfileContent), 0644)
		require.NoError(t, err, "Failed to write initial almd-lock.toml")
	}

	for relPath, content := range mockDepFiles {
		absPath := filepath.Join(tempDir, relPath)
		err := os.MkdirAll(filepath.Dir(absPath), 0755)
		require.NoError(t, err, "Failed to create directory for mock dep file: %s", filepath.Dir(absPath))
		err = os.WriteFile(absPath, []byte(content), 0644)
		require.NoError(t, err, "Failed to write mock dependency file: %s", absPath)
	}

	return tempDir
}

// runInstallCommand executes the 'install' command in a specified directory.
// It temporarily changes the working directory, runs the command, and ensures
// the original working directory is restored, even if the command fails.
func runInstallCommand(t *testing.T, workDir string, installCmdArgs ...string) error {
	t.Helper()

	originalWd, err := os.Getwd()
	require.NoError(t, err, "Failed to get current working directory")
	err = os.Chdir(workDir)
	require.NoError(t, err, "Failed to change to working directory: %s", workDir)
	defer func() {
		require.NoError(t, os.Chdir(originalWd), "Failed to restore original working directory")
	}()

	app := &cli.App{
		Name: "almd-test-install",
		Commands: []*cli.Command{
			installcmd.InstallCmd(),
		},
		Writer:    os.Stderr,
		ErrWriter: os.Stderr,
		ExitErrHandler: func(context *cli.Context, err error) {
			// Do nothing, let test assertions handle errors
		},
	}

	cliArgs := []string{"almd-test-install", "install"}
	cliArgs = append(cliArgs, installCmdArgs...)

	return app.Run(cliArgs)
}

// readProjectToml reads and unmarshals the project.toml file into a Project struct.
// It ensures the file exists and is valid TOML.
func readProjectToml(t *testing.T, tomlPath string) project.Project {
	t.Helper()
	bytes, err := os.ReadFile(tomlPath)
	require.NoError(t, err, "Failed to read project.toml: %s", tomlPath)

	var projCfg project.Project
	err = toml.Unmarshal(bytes, &projCfg)
	require.NoError(t, err, "Failed to unmarshal project.toml: %s", tomlPath)
	return projCfg
}

// readAlmdLockToml reads and unmarshals the almd-lock.toml file into a Lockfile struct.
// It ensures the file exists and is valid TOML.
func readAlmdLockToml(t *testing.T, lockPath string) lockfile.Lockfile {
	t.Helper()
	bytes, err := os.ReadFile(lockPath)
	require.NoError(t, err, "Failed to read almd-lock.toml: %s", lockPath)

	var lockCfg lockfile.Lockfile
	err = toml.Unmarshal(bytes, &lockCfg)
	require.NoError(t, err, "Failed to unmarshal almd-lock.toml: %s", lockPath)
	return lockCfg
}

// TestInstallCommand_OneDepNeedsUpdate_CommitHashChange verifies that when a dependency's
// remote commit changes, the install command correctly downloads and updates the file
// and lockfile while preserving project.toml.
func TestInstallCommand_OneDepNeedsUpdate_CommitHashChange(t *testing.T) {
	// Test setup and assertions for dependency update scenario
	depAName := "depA"
	depAPath := "libs/depA.lua"
	depAOriginalContent := "local depA_v1 = true"
	depANewContent := "local depA_v2 = true; print('updated')"

	initialProjectToml := fmt.Sprintf(`
[package]
name = "test-install-project"
version = "0.1.0"

[dependencies.%s]
source = "github:testowner/testrepo/%s@main"
path = "%s"
`, depAName, depAPath, depAPath)

	initialLockfile := fmt.Sprintf(`
api_version = "1"

[package.%s]
source = "https://raw.githubusercontent.com/testowner/testrepo/commit1_sha_abcdef1234567890/%s"
path = "%s"
hash = "commit:commit1_sha_abcdef1234567890"
`, depAName, depAPath, depAPath)

	mockFiles := map[string]string{
		depAPath: depAOriginalContent,
	}

	tempDir := setupInstallTestEnvironment(t, initialProjectToml, initialLockfile, mockFiles)

	commit2SHA := "fedcba0987654321abcdef1234567890"
	githubAPIPathForDepA := fmt.Sprintf("/repos/testowner/testrepo/commits?path=%s&sha=main&per_page=1", depAPath)
	githubAPIResponseForDepA := fmt.Sprintf(`[{"sha": "%s"}]`, commit2SHA)
	rawDownloadPathDepA := fmt.Sprintf("/testowner/testrepo/%s/%s", commit2SHA, depAPath)

	pathResps := map[string]struct {
		Body string
		Code int
	}{
		githubAPIPathForDepA: {Body: githubAPIResponseForDepA, Code: http.StatusOK},
		rawDownloadPathDepA:  {Body: depANewContent, Code: http.StatusOK},
	}
	mockServer := startMockHTTPServer(t, pathResps)

	originalGHAPIBaseURL := source.GithubAPIBaseURL
	source.GithubAPIBaseURL = mockServer.URL
	defer func() { source.GithubAPIBaseURL = originalGHAPIBaseURL }()

	err := runInstallCommand(t, tempDir)
	require.NoError(t, err, "almd install command failed")

	depAFilePath := filepath.Join(tempDir, depAPath)
	updatedContentBytes, readErr := os.ReadFile(depAFilePath)
	require.NoError(t, readErr, "Failed to read updated depA file: %s", depAFilePath)
	assert.Equal(t, depANewContent, string(updatedContentBytes), "depA file content mismatch after install")

	lockFilePath := filepath.Join(tempDir, lockfile.LockfileName)
	updatedLockCfg := readAlmdLockToml(t, lockFilePath)

	require.NotNil(t, updatedLockCfg.Package, "Packages map in almd-lock.toml is nil after install")
	depALockEntry, ok := updatedLockCfg.Package[depAName]
	require.True(t, ok, "depA entry not found in almd-lock.toml after install")

	expectedLockSourceURL := mockServer.URL + rawDownloadPathDepA
	assert.Equal(t, expectedLockSourceURL, depALockEntry.Source, "depA lockfile source URL mismatch")
	assert.Equal(t, depAPath, depALockEntry.Path, "depA lockfile path mismatch")
	assert.Equal(t, "commit:"+commit2SHA, depALockEntry.Hash, "depA lockfile hash mismatch")

	projTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	currentProjCfg := readProjectToml(t, projTomlPath)
	depAProjEntry, ok := currentProjCfg.Dependencies[depAName]
	require.True(t, ok, "depA entry not found in project.toml")
	assert.Equal(t, fmt.Sprintf("github:testowner/testrepo/%s@main", depAPath), depAProjEntry.Source, "project.toml source for depA should not change")
}

// TestInstallCommand_SpecificDepInstall_OneNeedsUpdate verifies that installing a specific
// dependency only updates that dependency, leaving others unchanged, even if they also
// have updates available.
func TestInstallCommand_SpecificDepInstall_OneNeedsUpdate(t *testing.T) {
	// Test setup and assertions for specific dependency install scenario
	depAName := "depA"
	depAPath := "libs/depA.lua"
	depAOriginalContent := "local depA_v1 = true"
	depANewContent := "local depA_v2 = true; print('updated A')"
	depACommit1HexSHA := "abcdef1234567890abcdef1234567890"
	depACommit2HexSHA := "fedcba0987654321fedcba0987654321"

	depBName := "depB"
	depBPath := "modules/depB.lua"
	depBOriginalContent := "local depB_v1 = true"
	depBNewContent := "local depB_v2 = true; print('updated B')"
	depBCommit1HexSHA := "1234567890abcdef1234567890abcdef"
	depBCommit2HexSHA := "0987654321fedcba0987654321fedcba"

	initialProjectToml := fmt.Sprintf(`
[package]
name = "test-specific-install"
version = "0.1.0"

[dependencies.%s]
source = "github:testowner/testrepo/%s@main"
path = "%s"

[dependencies.%s]
source = "github:anotherowner/anotherrepo/%s@main"
path = "%s"
`, depAName, depAPath, depAPath, depBName, depBPath, depBPath)

	initialLockfile := fmt.Sprintf(`
api_version = "1"

[package.%s]
source = "https://raw.githubusercontent.com/testowner/testrepo/%s/%s"
path = "%s"
hash = "commit:%s"

[package.%s]
source = "https://raw.githubusercontent.com/anotherowner/anotherrepo/%s/%s"
path = "%s"
hash = "commit:%s"
`, depAName, depACommit1HexSHA, depAPath, depAPath, depACommit1HexSHA,
		depBName, depBCommit1HexSHA, depBPath, depBPath, depBCommit1HexSHA)

	mockFiles := map[string]string{
		depAPath: depAOriginalContent,
		depBPath: depBOriginalContent,
	}

	tempDir := setupInstallTestEnvironment(t, initialProjectToml, initialLockfile, mockFiles)

	githubAPIPathForDepA := fmt.Sprintf("/repos/testowner/testrepo/commits?path=%s&sha=main&per_page=1", depAPath)
	githubAPIResponseForDepA := fmt.Sprintf(`[{"sha": "%s"}]`, depACommit2HexSHA)
	rawDownloadPathDepA := fmt.Sprintf("/testowner/testrepo/%s/%s", depACommit2HexSHA, depAPath)

	githubAPIPathForDepB := fmt.Sprintf("/repos/anotherowner/anotherrepo/commits?path=%s&sha=main&per_page=1", depBPath)
	githubAPIResponseForDepB := fmt.Sprintf(`[{"sha": "%s"}]`, depBCommit2HexSHA)
	rawDownloadPathDepB := fmt.Sprintf("/anotherowner/anotherrepo/%s/%s", depBCommit2HexSHA, depBPath)

	pathResps := map[string]struct {
		Body string
		Code int
	}{
		githubAPIPathForDepA: {Body: githubAPIResponseForDepA, Code: http.StatusOK},
		rawDownloadPathDepA:  {Body: depANewContent, Code: http.StatusOK},
		githubAPIPathForDepB: {Body: githubAPIResponseForDepB, Code: http.StatusOK},
		rawDownloadPathDepB:  {Body: depBNewContent, Code: http.StatusOK},
	}
	mockServer := startMockHTTPServer(t, pathResps)

	originalGHAPIBaseURL := source.GithubAPIBaseURL
	source.GithubAPIBaseURL = mockServer.URL
	defer func() { source.GithubAPIBaseURL = originalGHAPIBaseURL }()

	err := runInstallCommand(t, tempDir, depAName)
	require.NoError(t, err, "almd install %s command failed", depAName)

	depAFilePath := filepath.Join(tempDir, depAPath)
	updatedContentBytesA, readErrA := os.ReadFile(depAFilePath)
	require.NoError(t, readErrA, "Failed to read updated depA file: %s", depAFilePath)
	assert.Equal(t, depANewContent, string(updatedContentBytesA), "depA file content mismatch after specific install")

	lockFilePath := filepath.Join(tempDir, lockfile.LockfileName)
	updatedLockCfg := readAlmdLockToml(t, lockFilePath)
	require.NotNil(t, updatedLockCfg.Package, "Packages map in almd-lock.toml is nil")

	depALockEntry, okA := updatedLockCfg.Package[depAName]
	require.True(t, okA, "depA entry not found in almd-lock.toml after specific install")
	expectedLockSourceURLA := mockServer.URL + rawDownloadPathDepA
	assert.Equal(t, expectedLockSourceURLA, depALockEntry.Source, "depA lockfile source URL mismatch")
	assert.Equal(t, "commit:"+depACommit2HexSHA, depALockEntry.Hash, "depA lockfile hash mismatch")

	depBFilePath := filepath.Join(tempDir, depBPath)
	contentBytesB, readErrB := os.ReadFile(depBFilePath)
	require.NoError(t, readErrB, "Failed to read depB file: %s", depBFilePath)
	assert.Equal(t, depBOriginalContent, string(contentBytesB), "depB file content should not have changed")

	depBLockEntry, okB := updatedLockCfg.Package[depBName]
	require.True(t, okB, "depB entry not found in almd-lock.toml")
	expectedLockSourceURLBOriginal := fmt.Sprintf("https://raw.githubusercontent.com/anotherowner/anotherrepo/%s/%s", depBCommit1HexSHA, depBPath)
	assert.Equal(t, expectedLockSourceURLBOriginal, depBLockEntry.Source, "depB lockfile source URL should be unchanged")
	assert.Equal(t, "commit:"+depBCommit1HexSHA, depBLockEntry.Hash, "depB lockfile hash should be unchanged")

	projTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	currentProjCfg := readProjectToml(t, projTomlPath)
	depAProjEntry := currentProjCfg.Dependencies[depAName]
	assert.Equal(t, fmt.Sprintf("github:testowner/testrepo/%s@main", depAPath), depAProjEntry.Source)
	depBProjEntry := currentProjCfg.Dependencies[depBName]
	assert.Equal(t, fmt.Sprintf("github:anotherowner/anotherrepo/%s@main", depBPath), depBProjEntry.Source)
}

// TestInstallCommand_AllDepsUpToDate verifies that when all dependencies are current,
// the install command makes no changes to files or lockfile entries.
func TestInstallCommand_AllDepsUpToDate(t *testing.T) {
	// Test setup and assertions for up-to-date dependencies scenario
	depAName := "depA"
	depAPath := "libs/depA.lua"
	depAContent := "local depA_v_current = true"
	depACommitCurrentSHA := "commitA_sha_current12345"

	initialProjectToml := fmt.Sprintf(`
[package]
name = "test-uptodate-project"
version = "0.1.0"

[dependencies.%s]
source = "github:testowner/testrepo/%s@main"
path = "%s"
`, depAName, depAPath, depAPath)

	initialLockfile := fmt.Sprintf(`
api_version = "1"

[package.%s]
source = "https://raw.githubusercontent.com/testowner/testrepo/%s/%s"
path = "%s"
hash = "commit:%s"
`, depAName, depACommitCurrentSHA, depAPath, depAPath, depACommitCurrentSHA)

	mockFiles := map[string]string{
		depAPath: depAContent,
	}

	tempDir := setupInstallTestEnvironment(t, initialProjectToml, initialLockfile, mockFiles)

	githubAPIPathForDepA := fmt.Sprintf("/repos/testowner/testrepo/commits?path=%s&sha=main&per_page=1", depAPath)
	githubAPIResponseForDepA := fmt.Sprintf(`[{"sha": "%s"}]`, depACommitCurrentSHA)
	rawDownloadPathDepA := fmt.Sprintf("/testowner/testrepo/%s/%s", depACommitCurrentSHA, depAPath)

	pathResps := map[string]struct {
		Body string
		Code int
	}{
		githubAPIPathForDepA: {Body: githubAPIResponseForDepA, Code: http.StatusOK},
		rawDownloadPathDepA:  {Body: depAContent, Code: http.StatusOK},
	}
	mockServer := startMockHTTPServer(t, pathResps)

	originalGHAPIBaseURL := source.GithubAPIBaseURL
	source.GithubAPIBaseURL = mockServer.URL
	defer func() { source.GithubAPIBaseURL = originalGHAPIBaseURL }()

	err := runInstallCommand(t, tempDir)
	require.NoError(t, err, "almd install command failed")

	depAFilePath := filepath.Join(tempDir, depAPath)
	currentContentBytes, readErr := os.ReadFile(depAFilePath)
	require.NoError(t, readErr, "Failed to read depA file: %s", depAFilePath)
	assert.Equal(t, depAContent, string(currentContentBytes), "depA file content should be unchanged")

	lockFilePath := filepath.Join(tempDir, lockfile.LockfileName)
	currentLockCfg := readAlmdLockToml(t, lockFilePath)
	originalLockCfg := lockfile.Lockfile{}
	errUnmarshal := toml.Unmarshal([]byte(initialLockfile), &originalLockCfg)
	require.NoError(t, errUnmarshal, "Failed to unmarshal original lockfile content for comparison")

	assert.Equal(t, originalLockCfg, currentLockCfg, "almd-lock.toml should be unchanged")

	projTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	currentProjCfg := readProjectToml(t, projTomlPath)
	originalProjCfg := project.Project{}
	errUnmarshalProj := toml.Unmarshal([]byte(initialProjectToml), &originalProjCfg)
	require.NoError(t, errUnmarshalProj, "Failed to unmarshal original project.toml content for comparison")
	assert.Equal(t, originalProjCfg, currentProjCfg, "project.toml should be unchanged")
}

// TestInstallCommand_DepInProjectToml_MissingFromLockfile verifies that dependencies
// present in project.toml but missing from the lockfile are correctly downloaded
// and added to the lockfile.
func TestInstallCommand_DepInProjectToml_MissingFromLockfile(t *testing.T) {
	// Test setup and assertions for missing lockfile entry scenario
	depNewName := "depNew"
	depNewPath := "libs/depNew.lua"
	depNewContent := "local depNewContent = true"
	depNewCommitSHA := "abcdef1234567890abcdef1234567890"

	initialProjectToml := fmt.Sprintf(`
[package]
name = "test-missing-lockfile-entry"
version = "0.1.0"

[dependencies.%s]
source = "github:testowner/newrepo/%s@main"
path = "%s"
`, depNewName, depNewPath, depNewPath)

	initialLockfile := `
api_version = "1"
[package]
`

	tempDir := setupInstallTestEnvironment(t, initialProjectToml, initialLockfile, nil)

	githubAPIPathForDepNew := fmt.Sprintf("/repos/testowner/newrepo/commits?path=%s&sha=main&per_page=1", depNewPath)
	githubAPIResponseForDepNew := fmt.Sprintf(`[{"sha": "%s"}]`, depNewCommitSHA)
	rawDownloadPathDepNew := fmt.Sprintf("/testowner/newrepo/%s/%s", depNewCommitSHA, depNewPath)

	pathResps := map[string]struct {
		Body string
		Code int
	}{
		githubAPIPathForDepNew: {Body: githubAPIResponseForDepNew, Code: http.StatusOK},
		rawDownloadPathDepNew:  {Body: depNewContent, Code: http.StatusOK},
	}
	mockServer := startMockHTTPServer(t, pathResps)

	originalGHAPIBaseURL := source.GithubAPIBaseURL
	source.GithubAPIBaseURL = mockServer.URL
	defer func() { source.GithubAPIBaseURL = originalGHAPIBaseURL }()

	err := runInstallCommand(t, tempDir)
	require.NoError(t, err, "almd install command failed")

	depNewFilePath := filepath.Join(tempDir, depNewPath)
	contentBytes, readErr := os.ReadFile(depNewFilePath)
	require.NoError(t, readErr, "Failed to read depNew file: %s", depNewFilePath)
	assert.Equal(t, depNewContent, string(contentBytes), "depNew file content mismatch")

	lockFilePath := filepath.Join(tempDir, lockfile.LockfileName)
	updatedLockCfg := readAlmdLockToml(t, lockFilePath)

	require.NotNil(t, updatedLockCfg.Package, "Packages map in almd-lock.toml is nil")
	depNewLockEntry, ok := updatedLockCfg.Package[depNewName]
	require.True(t, ok, "depNew entry not found in almd-lock.toml after install")

	expectedLockSourceURL := mockServer.URL + rawDownloadPathDepNew
	assert.Equal(t, expectedLockSourceURL, depNewLockEntry.Source, "depNew lockfile source URL mismatch")
	assert.Equal(t, depNewPath, depNewLockEntry.Path, "depNew lockfile path mismatch")
	assert.Equal(t, "commit:"+depNewCommitSHA, depNewLockEntry.Hash, "depNew lockfile hash mismatch")
}

// TestInstallCommand_LocalFileMissing verifies that when a dependency's local file
// is missing but its lockfile entry exists, the file is re-downloaded using the
// locked source if the remote version matches.
func TestInstallCommand_LocalFileMissing(t *testing.T) {
	// Test setup and assertions for missing local file scenario
	depAName := "depA"
	depAPath := "libs/depA.lua"
	depAContent := "local depA_content_from_lock = true"
	depALockedCommitSHA := "fedcba0987654321fedcba0987654321"

	initialProjectToml := fmt.Sprintf(`
[package]
name = "test-local-file-missing"
version = "0.1.0"

[dependencies.%s]
source = "github:testowner/testrepo/%s@main"
path = "%s"
`, depAName, depAPath, depAPath)

	initialLockfile := fmt.Sprintf(`
api_version = "1"

[package.%s]
source = "https://raw.githubusercontent.com/testowner/testrepo/%s/%s"
path = "%s"
hash = "commit:%s"
`, depAName, depALockedCommitSHA, depAPath, depAPath, depALockedCommitSHA)

	tempDir := setupInstallTestEnvironment(t, initialProjectToml, initialLockfile, nil)

	githubAPIPathForDepA := fmt.Sprintf("/repos/testowner/testrepo/commits?path=%s&sha=main&per_page=1", depAPath)
	githubAPIResponseForDepA := fmt.Sprintf(`[{"sha": "%s"}]`, depALockedCommitSHA)
	rawDownloadPathDepA := fmt.Sprintf("/testowner/testrepo/%s/%s", depALockedCommitSHA, depAPath)

	pathResps := map[string]struct {
		Body string
		Code int
	}{
		githubAPIPathForDepA: {Body: githubAPIResponseForDepA, Code: http.StatusOK},
		rawDownloadPathDepA:  {Body: depAContent, Code: http.StatusOK},
	}
	mockServer := startMockHTTPServer(t, pathResps)

	originalGHAPIBaseURL := source.GithubAPIBaseURL
	source.GithubAPIBaseURL = mockServer.URL
	defer func() { source.GithubAPIBaseURL = originalGHAPIBaseURL }()

	err := runInstallCommand(t, tempDir, depAName)
	require.NoError(t, err, "almd install %s command failed", depAName)

	depAFilePath := filepath.Join(tempDir, depAPath)
	contentBytes, readErr := os.ReadFile(depAFilePath)
	require.NoError(t, readErr, "Failed to read re-downloaded depA file: %s", depAFilePath)
	assert.Equal(t, depAContent, string(contentBytes), "depA file content mismatch after re-download")

	lockFilePath := filepath.Join(tempDir, lockfile.LockfileName)
	updatedLockCfg := readAlmdLockToml(t, lockFilePath)

	require.NotNil(t, updatedLockCfg.Package, "Packages map in almd-lock.toml is nil")
	depALockEntry, ok := updatedLockCfg.Package[depAName]
	require.True(t, ok, "depA entry not found in almd-lock.toml after install")

	expectedLockSourceURL := mockServer.URL + rawDownloadPathDepA
	assert.Equal(t, expectedLockSourceURL, depALockEntry.Source, "depA lockfile source URL mismatch")
	assert.Equal(t, depAPath, depALockEntry.Path, "depA lockfile path mismatch")
	assert.Equal(t, "commit:"+depALockedCommitSHA, depALockEntry.Hash, "depA lockfile hash mismatch")
}

// TestInstallCommand_ForceInstallUpToDateDependency verifies that the --force flag
// causes re-download of dependencies even when they're up to date, ensuring the
// local files match their remote versions exactly.
func TestInstallCommand_ForceInstallUpToDateDependency(t *testing.T) {
	// Test setup and assertions for force install scenario
	depAName := "depA"
	depAPath := "libs/depA.lua"
	depAContent := "local depA_v_current = true"
	depACommitCurrentSHA := "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"

	initialProjectToml := fmt.Sprintf(`
[package]
name = "test-force-install-project"
version = "0.1.0"

[dependencies.%s]
source = "github:testowner/testrepo/%s@main"
path = "%s"
`, depAName, depAPath, depAPath)

	initialLockfileContent := fmt.Sprintf(`
api_version = "1"

[package.%s]
source = "https://raw.githubusercontent.com/testowner/testrepo/%s/%s"
path = "%s"
hash = "commit:%s"
`, depAName, depACommitCurrentSHA, depAPath, depAPath, depACommitCurrentSHA)

	mockFiles := map[string]string{
		depAPath: depAContent,
	}

	tempDir := setupInstallTestEnvironment(t, initialProjectToml, initialLockfileContent, mockFiles)

	githubAPIPathForDepA := fmt.Sprintf("/repos/testowner/testrepo/commits?path=%s&sha=main&per_page=1", depAPath)
	githubAPIResponseForDepA := fmt.Sprintf(`[{"sha": "%s"}]`, depACommitCurrentSHA)
	rawDownloadPathDepA := fmt.Sprintf("/testowner/testrepo/%s/%s", depACommitCurrentSHA, depAPath)

	downloadEndpointCalled := false
	pathResps := map[string]struct {
		Body string
		Code int
	}{
		githubAPIPathForDepA: {Body: githubAPIResponseForDepA, Code: http.StatusOK},
		rawDownloadPathDepA: {
			Body: depAContent,
			Code: http.StatusOK,
		},
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestPathWithQuery := r.URL.Path
		if r.URL.RawQuery != "" {
			requestPathWithQuery += "?" + r.URL.RawQuery
		}

		if r.Method == http.MethodGet && (r.URL.Path == rawDownloadPathDepA || requestPathWithQuery == rawDownloadPathDepA) {
			downloadEndpointCalled = true
		}

		for path, response := range pathResps {
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
	t.Cleanup(server.Close)
	mockServerURL := server.URL

	originalGHAPIBaseURL := source.GithubAPIBaseURL
	source.GithubAPIBaseURL = mockServerURL
	defer func() { source.GithubAPIBaseURL = originalGHAPIBaseURL }()

	err := runInstallCommand(t, tempDir, "--force", depAName)
	require.NoError(t, err, "almd install --force %s command failed", depAName)

	assert.True(t, downloadEndpointCalled, "Download endpoint for depA was not called despite --force")

	depAFilePath := filepath.Join(tempDir, depAPath)
	currentContentBytes, readErr := os.ReadFile(depAFilePath)
	require.NoError(t, readErr, "Failed to read depA file: %s", depAFilePath)
	assert.Equal(t, depAContent, string(currentContentBytes), "depA file content should be (re-)written")

	lockFilePath := filepath.Join(tempDir, lockfile.LockfileName)
	updatedLockCfg := readAlmdLockToml(t, lockFilePath)

	require.NotNil(t, updatedLockCfg.Package, "Packages map in almd-lock.toml is nil after force install")
	depALockEntry, ok := updatedLockCfg.Package[depAName]
	require.True(t, ok, "depA entry not found in almd-lock.toml after force install")

	expectedLockSourceURL := mockServerURL + rawDownloadPathDepA
	assert.Equal(t, expectedLockSourceURL, depALockEntry.Source, "depA lockfile source URL mismatch after force")
	assert.Equal(t, depAPath, depALockEntry.Path, "depA lockfile path mismatch after force")
	assert.Equal(t, "commit:"+depACommitCurrentSHA, depALockEntry.Hash, "depA lockfile hash mismatch after force")

	projTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	currentProjCfg := readProjectToml(t, projTomlPath)
	originalProjCfg := project.Project{}
	errUnmarshalProj := toml.Unmarshal([]byte(initialProjectToml), &originalProjCfg)
	require.NoError(t, errUnmarshalProj, "Failed to unmarshal original project.toml content for comparison")
	assert.Equal(t, originalProjCfg, currentProjCfg, "project.toml should be unchanged after force install")
}

// TestInstallCommand_NonExistentDependencySpecified verifies that attempting to
// install a non-existent dependency results in a warning message without modifying
// any files or the lockfile.
func TestInstallCommand_NonExistentDependencySpecified(t *testing.T) {
	// Test setup and assertions for non-existent dependency scenario
	nonExistentDepName := "nonExistentDep"

	initialProjectToml := `
[package]
name = "test-nonexistent-dep-project"
version = "0.1.0"
`

	initialLockfileContent := `
api_version = "1"
[package]
`

	tempDir := setupInstallTestEnvironment(t, initialProjectToml, initialLockfileContent, nil)

	err := runInstallCommand(t, tempDir, nonExistentDepName)
	require.NoError(t, err, "almd install %s command failed unexpectedly (expected warning, not fatal error)", nonExistentDepName)

	projTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	currentProjCfg := readProjectToml(t, projTomlPath)
	originalProjCfg := project.Project{}
	errUnmarshalProj := toml.Unmarshal([]byte(initialProjectToml), &originalProjCfg)
	require.NoError(t, errUnmarshalProj, "Failed to unmarshal original project.toml content for comparison")
	assert.Equal(t, originalProjCfg, currentProjCfg, "project.toml should be unchanged")

	lockFilePath := filepath.Join(tempDir, lockfile.LockfileName)
	currentLockCfg := readAlmdLockToml(t, lockFilePath)
	originalLockCfg := lockfile.Lockfile{}
	errUnmarshalLock := toml.Unmarshal([]byte(initialLockfileContent), &originalLockCfg)
	require.NoError(t, errUnmarshalLock, "Failed to unmarshal original lockfile content for comparison")
	assert.Equal(t, originalLockCfg, currentLockCfg, "almd-lock.toml should be unchanged")

	libsDir := filepath.Join(tempDir, "libs")
	_, errStatLibs := os.Stat(libsDir)
	assert.True(t, os.IsNotExist(errStatLibs), "libs directory should not have been created")

	vendorDir := filepath.Join(tempDir, "vendor")
	_, errStatVendor := os.Stat(vendorDir)
	assert.True(t, os.IsNotExist(errStatVendor), "vendor directory should not have been created")

	nonExistentDepFilePath := filepath.Join(tempDir, nonExistentDepName)
	_, errStatDepFile := os.Stat(nonExistentDepFilePath)
	assert.True(t, os.IsNotExist(errStatDepFile), "File for nonExistentDep should not have been created")
}

// TestInstallCommand_ErrorDuringDownload verifies that download failures are
// handled gracefully, leaving files and lockfile in their original state.
func TestInstallCommand_ErrorDuringDownload(t *testing.T) {
	// Test setup and assertions for download error scenario
	depName := "depWithError"
	depPath := "libs/depWithError.lua"
	depOriginalContent := "local depWithError_v1 = true"

	initialProjectToml := fmt.Sprintf(`
[package]
name = "test-download-error-project"
version = "0.1.0"

[dependencies.%s]
source = "github:testowner/testrepo/%s@main"
path = "%s"
`, depName, depPath, depPath)

	initialLockfile := fmt.Sprintf(`
api_version = "1"

[package.%s]
source = "https://raw.githubusercontent.com/testowner/testrepo/commit1_sha_dlerror/%s"
path = "%s"
hash = "commit:commit1_sha_dlerror"
`, depName, depPath, depPath)

	mockFiles := map[string]string{
		depPath: depOriginalContent,
	}

	tempDir := setupInstallTestEnvironment(t, initialProjectToml, initialLockfile, mockFiles)

	commitToDownloadSHA := "commit2_sha_dlerror_target"
	githubAPIPathForDep := fmt.Sprintf("/repos/testowner/testrepo/commits?path=%s&sha=main&per_page=1", depPath)
	githubAPIResponseForDep := fmt.Sprintf(`[{"sha": "%s"}]`, commitToDownloadSHA)

	rawDownloadPathDep := fmt.Sprintf("/testowner/testrepo/%s/%s", commitToDownloadSHA, depPath)

	pathResps := map[string]struct {
		Body string
		Code int
	}{
		githubAPIPathForDep: {Body: githubAPIResponseForDep, Code: http.StatusOK},
		rawDownloadPathDep:  {Body: "Simulated server error", Code: http.StatusInternalServerError},
	}
	mockServer := startMockHTTPServer(t, pathResps)

	originalGHAPIBaseURL := source.GithubAPIBaseURL
	source.GithubAPIBaseURL = mockServer.URL
	defer func() { source.GithubAPIBaseURL = originalGHAPIBaseURL }()

	err := runInstallCommand(t, tempDir)
	require.Error(t, err, "almd install command should have failed due to download error")

	depFilePath := filepath.Join(tempDir, depPath)
	currentContentBytes, readErr := os.ReadFile(depFilePath)
	require.NoError(t, readErr, "Failed to read depWithError file: %s", depFilePath)
	assert.Equal(t, depOriginalContent, string(currentContentBytes), "depWithError file content should be unchanged after failed download")

	lockFilePath := filepath.Join(tempDir, lockfile.LockfileName)
	currentLockCfg := readAlmdLockToml(t, lockFilePath)
	originalLockCfg := lockfile.Lockfile{}
	errUnmarshal := toml.Unmarshal([]byte(initialLockfile), &originalLockCfg)
	require.NoError(t, errUnmarshal, "Failed to unmarshal original lockfile content for comparison")
	assert.Equal(t, originalLockCfg, currentLockCfg, "almd-lock.toml should be unchanged after failed download")

	projTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	currentProjCfg := readProjectToml(t, projTomlPath)
	originalProjCfg := project.Project{}
	errUnmarshalProj := toml.Unmarshal([]byte(initialProjectToml), &originalProjCfg)
	require.NoError(t, errUnmarshalProj, "Failed to unmarshal original project.toml content for comparison")
	assert.Equal(t, originalProjCfg, currentProjCfg, "project.toml should be unchanged")
}

// TestInstallCommand_ErrorDuringSourceResolution verifies that source resolution
// failures (e.g., non-existent branch) are handled gracefully without creating
// incomplete or corrupted dependency files.
func TestInstallCommand_ErrorDuringSourceResolution(t *testing.T) {
	// Test setup and assertions for source resolution error scenario
	depName := "depBadBranch"
	depPath := "libs/depBadBranch.lua"
	nonExistentBranch := "nonexistent_branch_for_sure"

	initialProjectToml := fmt.Sprintf(`
[package]
name = "test-source-resolution-error-project"
version = "0.1.0"

[dependencies.%s]
source = "github:testowner/testrepo/%s@%s"
path = "%s"
`, depName, depPath, nonExistentBranch, depPath)

	initialLockfile := `
api_version = "1"
[package]
`

	tempDir := setupInstallTestEnvironment(t, initialProjectToml, initialLockfile, nil)

	githubAPIPathForDep := fmt.Sprintf("/repos/testowner/testrepo/commits?path=%s&sha=%s&per_page=1", depPath, nonExistentBranch)
	githubAPIResponseForDep_NotFound := `[]`

	rawDownloadPathDep := fmt.Sprintf("/testowner/testrepo/some_sha_never_reached/%s", depPath)

	pathResps := map[string]struct {
		Body string
		Code int
	}{
		githubAPIPathForDep: {Body: githubAPIResponseForDep_NotFound, Code: http.StatusOK},
		rawDownloadPathDep:  {Body: "SHOULD NOT BE DOWNLOADED", Code: http.StatusOK},
	}
	mockServer := startMockHTTPServer(t, pathResps)

	originalGHAPIBaseURL := source.GithubAPIBaseURL
	source.GithubAPIBaseURL = mockServer.URL
	defer func() { source.GithubAPIBaseURL = originalGHAPIBaseURL }()

	err := runInstallCommand(t, tempDir, depName)
	require.Error(t, err, "almd install command should have failed due to source resolution error")

	depFilePath := filepath.Join(tempDir, depPath)
	_, statErr := os.Stat(depFilePath)
	assert.True(t, os.IsNotExist(statErr), "depBadBranch file should not have been created")

	lockFilePath := filepath.Join(tempDir, lockfile.LockfileName)
	currentLockCfg := readAlmdLockToml(t, lockFilePath)
	originalLockCfg := lockfile.Lockfile{}
	errUnmarshal := toml.Unmarshal([]byte(initialLockfile), &originalLockCfg)
	require.NoError(t, errUnmarshal, "Failed to unmarshal original lockfile content for comparison")
	assert.Equal(t, originalLockCfg, currentLockCfg, "almd-lock.toml should be unchanged after source resolution error")

	projTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	currentProjCfg := readProjectToml(t, projTomlPath)
	originalProjCfg := project.Project{}
	errUnmarshalProj := toml.Unmarshal([]byte(initialProjectToml), &originalProjCfg)
	require.NoError(t, errUnmarshalProj, "Failed to unmarshal original project.toml content for comparison")
	assert.Equal(t, originalProjCfg, currentProjCfg, "project.toml should be unchanged")
}

// TestInstallCommand_ProjectTomlNotFound verifies that the install command fails
// with an appropriate error message when project.toml is missing from the current
// directory.
func TestInstallCommand_ProjectTomlNotFound(t *testing.T) {
	// Test setup and assertions for missing project.toml scenario
	tempDir := setupInstallTestEnvironment(t, "", "", nil)

	err := runInstallCommand(t, tempDir)

	require.Error(t, err, "almd install should return an error when project.toml is not found")
	assert.Contains(t, err.Error(), config.ProjectTomlName, "Error message should mention project.toml")
	assert.Contains(t, err.Error(), "not found in the current directory", "Error message should indicate file not found in current directory")
}
