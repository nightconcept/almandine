// Title: Almandine CLI Install Command Tests
// Purpose: Contains test cases for the 'install' command of the Almandine CLI.
package install_test

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/BurntSushi/toml"
	installcmd "github.com/nightconcept/almandine/internal/cli/install" // Import the package being tested
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

// startMockHTTPServer starts an httptest.Server that serves specific responses
// for a map of expected paths. Other paths will result in a 404.
// Adapted from add_test.go
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

// setupInstallTestEnvironment creates a temporary directory for testing and initializes
// project.toml, almd-lock.toml, and optionally mock dependency files.
// Returns the path to the temporary directory.
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

// runInstallCommand executes the 'install' command within a specific working directory.
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

// Helper to read project.toml, adapted from add_test.go
func readProjectToml(t *testing.T, tomlPath string) project.Project {
	t.Helper()
	bytes, err := os.ReadFile(tomlPath)
	require.NoError(t, err, "Failed to read project.toml: %s", tomlPath)

	var projCfg project.Project
	err = toml.Unmarshal(bytes, &projCfg)
	require.NoError(t, err, "Failed to unmarshal project.toml: %s", tomlPath)
	return projCfg
}

// Helper to read almd-lock.toml, adapted from add_test.go
func readAlmdLockToml(t *testing.T, lockPath string) lockfile.Lockfile {
	t.Helper()
	bytes, err := os.ReadFile(lockPath)
	require.NoError(t, err, "Failed to read almd-lock.toml: %s", lockPath)

	var lockCfg lockfile.Lockfile
	err = toml.Unmarshal(bytes, &lockCfg)
	require.NoError(t, err, "Failed to unmarshal almd-lock.toml: %s", lockPath)
	return lockCfg
}

// Task 7.2.1: Test `almd install` - All dependencies, one needs install (commit hash change)
func TestInstallCommand_OneDepNeedsUpdate_CommitHashChange(t *testing.T) {
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
`, depAName, depAPath, depAPath) // Assuming file name in repo is same as path for simplicity

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

	// Mock server setup
	// 1. GitHub API call to resolve 'main' for depA to a valid hex commit SHA
	// 2. Raw content download for depA using that commit SHA
	commit2SHA := "fedcba0987654321abcdef1234567890" // Valid hex SHA
	// Path for GetLatestCommitSHAForFile: /repos/<owner>/<repo>/commits?path=<file_path_in_repo>&sha=<ref>&per_page=1
	// The <file_path_in_repo> is extracted from the canonical source string.
	// Canonical source: "github:testowner/testrepo/libs/depA.lua@main" -> file_path_in_repo: "libs/depA.lua"
	githubAPIPathForDepA := fmt.Sprintf("/repos/testowner/testrepo/commits?path=%s&sha=main&per_page=1", depAPath)
	githubAPIResponseForDepA := fmt.Sprintf(`[{"sha": "%s"}]`, commit2SHA)

	// Raw download URL path for depA with new commit
	// source.go constructs this as: /<owner>/<repo>/<commit_sha>/<file_path_in_repo>
	// when testModeBypassHostValidation is true.
	rawDownloadPathDepA := fmt.Sprintf("/testowner/testrepo/%s/%s", commit2SHA, depAPath)

	pathResps := map[string]struct {
		Body string
		Code int
	}{
		githubAPIPathForDepA: {Body: githubAPIResponseForDepA, Code: http.StatusOK},
		rawDownloadPathDepA:  {Body: depANewContent, Code: http.StatusOK},
	}
	mockServer := startMockHTTPServer(t, pathResps)

	// Override GitHub API base URL to point to mock server
	originalGHAPIBaseURL := source.GithubAPIBaseURL
	source.GithubAPIBaseURL = mockServer.URL
	defer func() { source.GithubAPIBaseURL = originalGHAPIBaseURL }()

	// Override Raw GitHub Content base URL (used by downloader if source.ParseSourceURL returns a raw URL directly)
	// For test mode, source.ParseSourceURL constructs a full mock server URL if it's a GitHub source.
	// So, this override might not be strictly necessary if GithubAPIBaseURL is correctly used by ParseSourceURL
	// to build the *raw* download URL for the mock server.
	// Let's assume source.ParseSourceURL will use the mockServer.URL correctly for raw downloads in test mode.

	// --- Run Command ---
	err := runInstallCommand(t, tempDir) // No specific args, should install all from project.toml
	require.NoError(t, err, "almd install command failed")

	// --- Assertions ---
	// 1. Verify depA file content is updated
	depAFilePath := filepath.Join(tempDir, depAPath)
	updatedContentBytes, readErr := os.ReadFile(depAFilePath)
	require.NoError(t, readErr, "Failed to read updated depA file: %s", depAFilePath)
	assert.Equal(t, depANewContent, string(updatedContentBytes), "depA file content mismatch after install")

	// 2. Verify almd-lock.toml is updated for depA
	lockFilePath := filepath.Join(tempDir, lockfile.LockfileName)
	updatedLockCfg := readAlmdLockToml(t, lockFilePath)

	require.NotNil(t, updatedLockCfg.Package, "Packages map in almd-lock.toml is nil after install")
	depALockEntry, ok := updatedLockCfg.Package[depAName]
	require.True(t, ok, "depA entry not found in almd-lock.toml after install")

	// Expected raw source URL in lockfile should point to the new commit on the mock server
	expectedLockSourceURL := mockServer.URL + rawDownloadPathDepA
	assert.Equal(t, expectedLockSourceURL, depALockEntry.Source, "depA lockfile source URL mismatch")
	assert.Equal(t, depAPath, depALockEntry.Path, "depA lockfile path mismatch")
	assert.Equal(t, "commit:"+commit2SHA, depALockEntry.Hash, "depA lockfile hash mismatch")

	// 3. Verify project.toml remains unchanged (install doesn't modify project.toml sources)
	projTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	currentProjCfg := readProjectToml(t, projTomlPath)
	depAProjEntry, ok := currentProjCfg.Dependencies[depAName]
	require.True(t, ok, "depA entry not found in project.toml")
	assert.Equal(t, fmt.Sprintf("github:testowner/testrepo/%s@main", depAPath), depAProjEntry.Source, "project.toml source for depA should not change")
}

// Task 7.2.2: Test `almd install <dep_name>` - Specific dependency install
func TestInstallCommand_SpecificDepInstall_OneNeedsUpdate(t *testing.T) {
	depAName := "depA"
	depAPath := "libs/depA.lua"
	depAOriginalContent := "local depA_v1 = true"
	depANewContent := "local depA_v2 = true; print('updated A')"
	depACommit1HexSHA := "abcdef1234567890abcdef1234567890" // Valid hex
	depACommit2HexSHA := "fedcba0987654321fedcba0987654321" // Valid hex

	depBName := "depB"
	depBPath := "modules/depB.lua"
	depBOriginalContent := "local depB_v1 = true"
	depBNewContent := "local depB_v2 = true; print('updated B')" // Should not be used
	depBCommit1HexSHA := "1234567890abcdef1234567890abcdef"      // Valid hex
	depBCommit2HexSHA := "0987654321fedcba0987654321fedcba"      // Valid hex

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

	// Mock server setup
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
		githubAPIPathForDepB: {Body: githubAPIResponseForDepB, Code: http.StatusOK}, // depB might be checked by source resolver even if not installed
		rawDownloadPathDepB:  {Body: depBNewContent, Code: http.StatusOK},           // Should not be called
	}
	mockServer := startMockHTTPServer(t, pathResps)

	originalGHAPIBaseURL := source.GithubAPIBaseURL
	source.GithubAPIBaseURL = mockServer.URL
	defer func() { source.GithubAPIBaseURL = originalGHAPIBaseURL }()

	// --- Run Command for depA only ---
	err := runInstallCommand(t, tempDir, depAName)
	require.NoError(t, err, "almd install %s command failed", depAName)

	// --- Assertions for depA ---
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

	// --- Assertions for depB (should be unchanged) ---
	depBFilePath := filepath.Join(tempDir, depBPath)
	contentBytesB, readErrB := os.ReadFile(depBFilePath)
	require.NoError(t, readErrB, "Failed to read depB file: %s", depBFilePath)
	assert.Equal(t, depBOriginalContent, string(contentBytesB), "depB file content should not have changed")

	depBLockEntry, okB := updatedLockCfg.Package[depBName]
	require.True(t, okB, "depB entry not found in almd-lock.toml")
	expectedLockSourceURLBOriginal := fmt.Sprintf("https://raw.githubusercontent.com/anotherowner/anotherrepo/%s/%s", depBCommit1HexSHA, depBPath) // Original URL
	assert.Equal(t, expectedLockSourceURLBOriginal, depBLockEntry.Source, "depB lockfile source URL should be unchanged")
	assert.Equal(t, "commit:"+depBCommit1HexSHA, depBLockEntry.Hash, "depB lockfile hash should be unchanged")

	// Verify project.toml remains unchanged
	projTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	currentProjCfg := readProjectToml(t, projTomlPath)
	depAProjEntry := currentProjCfg.Dependencies[depAName]
	assert.Equal(t, fmt.Sprintf("github:testowner/testrepo/%s@main", depAPath), depAProjEntry.Source)
	depBProjEntry := currentProjCfg.Dependencies[depBName]
	assert.Equal(t, fmt.Sprintf("github:anotherowner/anotherrepo/%s@main", depBPath), depBProjEntry.Source)
}

// Task 7.2.3: Test `almd install` - All dependencies up-to-date
func TestInstallCommand_AllDepsUpToDate(t *testing.T) {
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

	// Lockfile points to the current commit, and local file matches this version
	initialLockfile := fmt.Sprintf(`
api_version = "1"

[package.%s]
source = "https://raw.githubusercontent.com/testowner/testrepo/%s/%s"
path = "%s"
hash = "commit:%s"
`, depAName, depACommitCurrentSHA, depAPath, depAPath, depACommitCurrentSHA)

	mockFiles := map[string]string{
		depAPath: depAContent, // Local file exists and is "current"
	}

	tempDir := setupInstallTestEnvironment(t, initialProjectToml, initialLockfile, mockFiles)

	// Mock server setup
	// GitHub API call to resolve 'main' for depA should return the *same* current SHA
	githubAPIPathForDepA := fmt.Sprintf("/repos/testowner/testrepo/commits?path=%s&sha=main&per_page=1", depAPath)
	githubAPIResponseForDepA := fmt.Sprintf(`[{"sha": "%s"}]`, depACommitCurrentSHA)

	// Raw download path - should ideally not be called if dep is up-to-date.
	// If it were called, it would serve the same content.
	rawDownloadPathDepA := fmt.Sprintf("/testowner/testrepo/%s/%s", depACommitCurrentSHA, depAPath)

	pathResps := map[string]struct {
		Body string
		Code int
	}{
		githubAPIPathForDepA: {Body: githubAPIResponseForDepA, Code: http.StatusOK},
		rawDownloadPathDepA:  {Body: depAContent, Code: http.StatusOK}, // Should not be fetched
	}
	mockServer := startMockHTTPServer(t, pathResps)

	originalGHAPIBaseURL := source.GithubAPIBaseURL
	source.GithubAPIBaseURL = mockServer.URL
	defer func() { source.GithubAPIBaseURL = originalGHAPIBaseURL }()

	// --- Run Command ---
	err := runInstallCommand(t, tempDir) // Install all
	require.NoError(t, err, "almd install command failed")

	// --- Assertions ---
	// 1. Verify depA file content is UNCHANGED
	depAFilePath := filepath.Join(tempDir, depAPath)
	currentContentBytes, readErr := os.ReadFile(depAFilePath)
	require.NoError(t, readErr, "Failed to read depA file: %s", depAFilePath)
	assert.Equal(t, depAContent, string(currentContentBytes), "depA file content should be unchanged")

	// 2. Verify almd-lock.toml is UNCHANGED
	lockFilePath := filepath.Join(tempDir, lockfile.LockfileName)
	currentLockCfg := readAlmdLockToml(t, lockFilePath) // Read current
	originalLockCfg := lockfile.Lockfile{}              // For comparison
	errUnmarshal := toml.Unmarshal([]byte(initialLockfile), &originalLockCfg)
	require.NoError(t, errUnmarshal, "Failed to unmarshal original lockfile content for comparison")

	assert.Equal(t, originalLockCfg, currentLockCfg, "almd-lock.toml should be unchanged")

	// 3. Verify project.toml remains unchanged
	projTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	currentProjCfg := readProjectToml(t, projTomlPath)
	originalProjCfg := project.Project{}
	errUnmarshalProj := toml.Unmarshal([]byte(initialProjectToml), &originalProjCfg)
	require.NoError(t, errUnmarshalProj, "Failed to unmarshal original project.toml content for comparison")
	assert.Equal(t, originalProjCfg, currentProjCfg, "project.toml should be unchanged")
}

// Task 7.2.4: Test `almd install` - Dependency in `project.toml` but missing from `almd-lock.toml`
func TestInstallCommand_DepInProjectToml_MissingFromLockfile(t *testing.T) {
	depNewName := "depNew"
	depNewPath := "libs/depNew.lua"
	depNewContent := "local depNewContent = true"
	depNewCommitSHA := "abcdef1234567890abcdef1234567890" // Valid hex

	initialProjectToml := fmt.Sprintf(`
[package]
name = "test-missing-lockfile-entry"
version = "0.1.0"

[dependencies.%s]
source = "github:testowner/newrepo/%s@main"
path = "%s"
`, depNewName, depNewPath, depNewPath)

	// Lockfile is initially empty or does not contain depNew
	initialLockfile := `
api_version = "1"
[package]
# depNew is missing here
`
	tempDir := setupInstallTestEnvironment(t, initialProjectToml, initialLockfile, nil) // No initial mock files for depNew

	// Mock server setup
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

	// --- Run Command ---
	err := runInstallCommand(t, tempDir) // Install all
	require.NoError(t, err, "almd install command failed")

	// --- Assertions ---
	// 1. Verify depNew file is created with correct content
	depNewFilePath := filepath.Join(tempDir, depNewPath)
	contentBytes, readErr := os.ReadFile(depNewFilePath)
	require.NoError(t, readErr, "Failed to read depNew file: %s", depNewFilePath)
	assert.Equal(t, depNewContent, string(contentBytes), "depNew file content mismatch")

	// 2. Verify almd-lock.toml is updated for depNew
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

// Task 7.2.5: Test `almd install` - Local dependency file missing
func TestInstallCommand_LocalFileMissing(t *testing.T) {
	depAName := "depA"
	depAPath := "libs/depA.lua"
	depAContent := "local depA_content_from_lock = true"      // Content served if lockfile's version is fetched
	depALockedCommitSHA := "fedcba0987654321fedcba0987654321" // Valid hex

	initialProjectToml := fmt.Sprintf(`
[package]
name = "test-local-file-missing"
version = "0.1.0"

[dependencies.%s]
source = "github:testowner/testrepo/%s@main" # 'main' might resolve to the same or different commit
path = "%s"
`, depAName, depAPath, depAPath)

	// Lockfile has depA, but its local file will be missing
	initialLockfile := fmt.Sprintf(`
api_version = "1"

[package.%s]
source = "https://raw.githubusercontent.com/testowner/testrepo/%s/%s" # URL with locked SHA
path = "%s"
hash = "commit:%s"
`, depAName, depALockedCommitSHA, depAPath, depAPath, depALockedCommitSHA)

	// No mock files initially for depA, simulating it's missing
	tempDir := setupInstallTestEnvironment(t, initialProjectToml, initialLockfile, nil)

	// Mock server setup
	// Case 1: 'main' in project.toml resolves to the *same* commit as in lockfile.
	// The install logic should then use the lockfile's source URL to re-download.
	githubAPIPathForDepA := fmt.Sprintf("/repos/testowner/testrepo/commits?path=%s&sha=main&per_page=1", depAPath)
	githubAPIResponseForDepA := fmt.Sprintf(`[{"sha": "%s"}]`, depALockedCommitSHA) // 'main' resolves to the locked SHA

	// Raw download path for depA using the locked commit SHA (from lockfile's source or resolved from project.toml)
	rawDownloadPathDepA := fmt.Sprintf("/testowner/testrepo/%s/%s", depALockedCommitSHA, depAPath)

	pathResps := map[string]struct {
		Body string
		Code int
	}{
		githubAPIPathForDepA: {Body: githubAPIResponseForDepA, Code: http.StatusOK},
		rawDownloadPathDepA:  {Body: depAContent, Code: http.StatusOK}, // Content for the locked SHA
	}
	mockServer := startMockHTTPServer(t, pathResps)

	originalGHAPIBaseURL := source.GithubAPIBaseURL
	source.GithubAPIBaseURL = mockServer.URL
	defer func() { source.GithubAPIBaseURL = originalGHAPIBaseURL }()

	// --- Run Command for depA ---
	err := runInstallCommand(t, tempDir, depAName)
	require.NoError(t, err, "almd install %s command failed", depAName)

	// --- Assertions ---
	// 1. Verify depA file is re-downloaded
	depAFilePath := filepath.Join(tempDir, depAPath)
	contentBytes, readErr := os.ReadFile(depAFilePath)
	require.NoError(t, readErr, "Failed to read re-downloaded depA file: %s", depAFilePath)
	assert.Equal(t, depAContent, string(contentBytes), "depA file content mismatch after re-download")

	// 2. Verify almd-lock.toml entry for depA is still correct (or updated if project.toml dictated newer)
	// In this test, since 'main' resolved to the same locked SHA, the lockfile entry should effectively be the same.
	lockFilePath := filepath.Join(tempDir, lockfile.LockfileName)
	updatedLockCfg := readAlmdLockToml(t, lockFilePath)

	require.NotNil(t, updatedLockCfg.Package, "Packages map in almd-lock.toml is nil")
	depALockEntry, ok := updatedLockCfg.Package[depAName]
	require.True(t, ok, "depA entry not found in almd-lock.toml after install")

	// Expected raw source URL in lockfile should point to the mock server's path for the locked commit
	expectedLockSourceURL := mockServer.URL + rawDownloadPathDepA
	assert.Equal(t, expectedLockSourceURL, depALockEntry.Source, "depA lockfile source URL mismatch")
	assert.Equal(t, depAPath, depALockEntry.Path, "depA lockfile path mismatch")
	assert.Equal(t, "commit:"+depALockedCommitSHA, depALockEntry.Hash, "depA lockfile hash mismatch")
}

// Task 7.2.6: Test `almd install --force` - Force install on an up-to-date dependency
func TestInstallCommand_ForceInstallUpToDateDependency(t *testing.T) {
	depAName := "depA"
	depAPath := "libs/depA.lua"
	depAContent := "local depA_v_current = true"
	depACommitCurrentSHA := "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2" // Valid 40-char hex

	initialProjectToml := fmt.Sprintf(`
[package]
name = "test-force-install-project"
version = "0.1.0"

[dependencies.%s]
source = "github:testowner/testrepo/%s@main"
path = "%s"
`, depAName, depAPath, depAPath)

	// Lockfile points to the current commit, and local file matches this version
	initialLockfileContent := fmt.Sprintf(`
api_version = "1"

[package.%s]
source = "https://raw.githubusercontent.com/testowner/testrepo/%s/%s"
path = "%s"
hash = "commit:%s"
`, depAName, depACommitCurrentSHA, depAPath, depAPath, depACommitCurrentSHA)

	mockFiles := map[string]string{
		depAPath: depAContent, // Local file exists and is "current"
	}

	tempDir := setupInstallTestEnvironment(t, initialProjectToml, initialLockfileContent, mockFiles)

	// Mock server setup
	// GitHub API call to resolve 'main' for depA should return the *same* current SHA
	githubAPIPathForDepA := fmt.Sprintf("/repos/testowner/testrepo/commits?path=%s&sha=main&per_page=1", depAPath)
	githubAPIResponseForDepA := fmt.Sprintf(`[{"sha": "%s"}]`, depACommitCurrentSHA)

	// Raw download path - this *should* be called due to --force
	rawDownloadPathDepA := fmt.Sprintf("/testowner/testrepo/%s/%s", depACommitCurrentSHA, depAPath)

	// Keep track of whether the download endpoint was called
	downloadEndpointCalled := false
	pathResps := map[string]struct {
		Body string
		Code int
	}{
		githubAPIPathForDepA: {Body: githubAPIResponseForDepA, Code: http.StatusOK},
		rawDownloadPathDepA: {
			Body: depAContent, // Serve the same content, or new if we want to check content update
			Code: http.StatusOK,
		},
	}

	// Modify the server to track the call
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

	// --- Run Command with --force ---
	// Note: urfave/cli parses flags before arguments.
	// So, `almd install depA --force` or `almd install --force depA` should work.
	// The task description uses `almd install --force depA`.
	err := runInstallCommand(t, tempDir, "--force", depAName)
	require.NoError(t, err, "almd install --force %s command failed", depAName)

	// --- Assertions ---
	assert.True(t, downloadEndpointCalled, "Download endpoint for depA was not called despite --force")

	// 1. Verify depA file content (could be same or updated if mock served new content)
	depAFilePath := filepath.Join(tempDir, depAPath)
	currentContentBytes, readErr := os.ReadFile(depAFilePath)
	require.NoError(t, readErr, "Failed to read depA file: %s", depAFilePath)
	assert.Equal(t, depAContent, string(currentContentBytes), "depA file content should be (re-)written")

	// 2. Verify almd-lock.toml is refreshed
	lockFilePath := filepath.Join(tempDir, lockfile.LockfileName)
	updatedLockCfg := readAlmdLockToml(t, lockFilePath)

	require.NotNil(t, updatedLockCfg.Package, "Packages map in almd-lock.toml is nil after force install")
	depALockEntry, ok := updatedLockCfg.Package[depAName]
	require.True(t, ok, "depA entry not found in almd-lock.toml after force install")

	expectedLockSourceURL := mockServerURL + rawDownloadPathDepA
	assert.Equal(t, expectedLockSourceURL, depALockEntry.Source, "depA lockfile source URL mismatch after force")
	assert.Equal(t, depAPath, depALockEntry.Path, "depA lockfile path mismatch after force")
	assert.Equal(t, "commit:"+depACommitCurrentSHA, depALockEntry.Hash, "depA lockfile hash mismatch after force (could be re-verified)")

	// 3. Verify project.toml remains unchanged
	projTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	currentProjCfg := readProjectToml(t, projTomlPath)
	originalProjCfg := project.Project{}
	errUnmarshalProj := toml.Unmarshal([]byte(initialProjectToml), &originalProjCfg)
	require.NoError(t, errUnmarshalProj, "Failed to unmarshal original project.toml content for comparison")
	assert.Equal(t, originalProjCfg, currentProjCfg, "project.toml should be unchanged after force install")
}

// Task 7.2.7: Test `almd install <non_existent_dep>` - Non-existent dependency specified
func TestInstallCommand_NonExistentDependencySpecified(t *testing.T) {
	nonExistentDepName := "nonExistentDep"

	initialProjectToml := `
[package]
name = "test-nonexistent-dep-project"
version = "0.1.0"
# No dependencies defined, or at least not nonExistentDep
`
	initialLockfileContent := `
api_version = "1"
[package]
`
	tempDir := setupInstallTestEnvironment(t, initialProjectToml, initialLockfileContent, nil)

	// No mock server needed as no downloads should occur for a non-existent dependency.

	// --- Run Command ---
	// We expect a warning, but the command itself might not return an error,
	// or it might return a specific error that indicates "not found but continued".
	// For now, we'll check that it doesn't panic and that files are unchanged.
	// Capturing stderr would be ideal for checking the warning.
	err := runInstallCommand(t, tempDir, nonExistentDepName)

	// Depending on implementation, this might be an error or not.
	// If it's just a warning, err might be nil.
	// For now, let's assume it might print a warning and continue without error if other deps were processed.
	// If only a non-existent dep is specified, it might still be a non-error exit.
	// The task says "Warning message printed, no other actions taken".
	// Let's assert no error for now, and focus on "no other actions taken".
	// If the command *does* return an error for this, this assertion will need adjustment.
	require.NoError(t, err, "almd install %s command failed unexpectedly (expected warning, not fatal error)", nonExistentDepName)

	// --- Assertions ---
	// 1. Verify project.toml remains unchanged
	projTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	currentProjCfg := readProjectToml(t, projTomlPath)
	originalProjCfg := project.Project{}
	errUnmarshalProj := toml.Unmarshal([]byte(initialProjectToml), &originalProjCfg)
	require.NoError(t, errUnmarshalProj, "Failed to unmarshal original project.toml content for comparison")
	assert.Equal(t, originalProjCfg, currentProjCfg, "project.toml should be unchanged")

	// 2. Verify almd-lock.toml remains unchanged
	lockFilePath := filepath.Join(tempDir, lockfile.LockfileName)
	currentLockCfg := readAlmdLockToml(t, lockFilePath)
	originalLockCfg := lockfile.Lockfile{}
	errUnmarshalLock := toml.Unmarshal([]byte(initialLockfileContent), &originalLockCfg)
	require.NoError(t, errUnmarshalLock, "Failed to unmarshal original lockfile content for comparison")
	assert.Equal(t, originalLockCfg, currentLockCfg, "almd-lock.toml should be unchanged")

	// 3. Verify no files were created in common dependency directories (e.g., libs, vendor)
	// This is a basic check; a more robust check would be to snapshot directory contents.
	libsDir := filepath.Join(tempDir, "libs")
	_, errStatLibs := os.Stat(libsDir)
	assert.True(t, os.IsNotExist(errStatLibs), "libs directory should not have been created")

	vendorDir := filepath.Join(tempDir, "vendor")
	_, errStatVendor := os.Stat(vendorDir)
	assert.True(t, os.IsNotExist(errStatVendor), "vendor directory should not have been created")

	// 4. Verify no file named nonExistentDep was created at root
	nonExistentDepFilePath := filepath.Join(tempDir, nonExistentDepName)
	_, errStatDepFile := os.Stat(nonExistentDepFilePath)
	assert.True(t, os.IsNotExist(errStatDepFile), "File for nonExistentDep should not have been created")
}

// Task 7.2.8: Test `almd install` - Error during download
func TestInstallCommand_ErrorDuringDownload(t *testing.T) {
	depName := "depWithError"
	depPath := "libs/depWithError.lua"
	depOriginalContent := "local depWithError_v1 = true"
	// depNewContent is not relevant as download will fail

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

	// Mock server setup
	commitToDownloadSHA := "commit2_sha_dlerror_target"
	githubAPIPathForDep := fmt.Sprintf("/repos/testowner/testrepo/commits?path=%s&sha=main&per_page=1", depPath)
	githubAPIResponseForDep := fmt.Sprintf(`[{"sha": "%s"}]`, commitToDownloadSHA)

	// This is the path that will fail
	rawDownloadPathDep := fmt.Sprintf("/testowner/testrepo/%s/%s", commitToDownloadSHA, depPath)

	pathResps := map[string]struct {
		Body string
		Code int
	}{
		githubAPIPathForDep: {Body: githubAPIResponseForDep, Code: http.StatusOK},
		rawDownloadPathDep:  {Body: "Simulated server error", Code: http.StatusInternalServerError}, // Download fails
	}
	mockServer := startMockHTTPServer(t, pathResps)

	originalGHAPIBaseURL := source.GithubAPIBaseURL
	source.GithubAPIBaseURL = mockServer.URL
	defer func() { source.GithubAPIBaseURL = originalGHAPIBaseURL }()

	// --- Run Command ---
	err := runInstallCommand(t, tempDir) // Install all
	require.Error(t, err, "almd install command should have failed due to download error")
	// Check for a more specific error if possible, e.g., by inspecting err.Error() or using cli.ExitCoder
	// For now, a general error check is fine. Example: assert.Contains(t, err.Error(), "failed to download")

	// --- Assertions ---
	// 1. Verify depWithError file content is UNCHANGED
	depFilePath := filepath.Join(tempDir, depPath)
	currentContentBytes, readErr := os.ReadFile(depFilePath)
	require.NoError(t, readErr, "Failed to read depWithError file: %s", depFilePath)
	assert.Equal(t, depOriginalContent, string(currentContentBytes), "depWithError file content should be unchanged after failed download")

	// 2. Verify almd-lock.toml is UNCHANGED
	lockFilePath := filepath.Join(tempDir, lockfile.LockfileName)
	currentLockCfg := readAlmdLockToml(t, lockFilePath)
	originalLockCfg := lockfile.Lockfile{}
	errUnmarshal := toml.Unmarshal([]byte(initialLockfile), &originalLockCfg)
	require.NoError(t, errUnmarshal, "Failed to unmarshal original lockfile content for comparison")
	assert.Equal(t, originalLockCfg, currentLockCfg, "almd-lock.toml should be unchanged after failed download")

	// 3. Verify project.toml remains unchanged
	projTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	currentProjCfg := readProjectToml(t, projTomlPath)
	originalProjCfg := project.Project{}
	errUnmarshalProj := toml.Unmarshal([]byte(initialProjectToml), &originalProjCfg)
	require.NoError(t, errUnmarshalProj, "Failed to unmarshal original project.toml content for comparison")
	assert.Equal(t, originalProjCfg, currentProjCfg, "project.toml should be unchanged")
}

// Task 7.2.9: Test `almd install` - Error during source resolution (e.g., branch not found)
func TestInstallCommand_ErrorDuringSourceResolution(t *testing.T) {
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
`, depName, depPath, nonExistentBranch, depPath) // Points to a non-existent branch

	// Lockfile might be empty or not contain this dep, or contain an old version.
	// The key is that resolution for the project.toml source will fail.
	initialLockfile := `
api_version = "1"
[package]
`
	// No initial mock file for depBadBranch as it shouldn't be downloaded.
	tempDir := setupInstallTestEnvironment(t, initialProjectToml, initialLockfile, nil)

	// Mock server setup
	// The GitHub API call to resolve 'nonexistent_branch_for_sure' should fail (e.g., 404 or empty array)
	githubAPIPathForDep := fmt.Sprintf("/repos/testowner/testrepo/commits?path=%s&sha=%s&per_page=1", depPath, nonExistentBranch)
	// GitHub API returns an empty array `[]` for a branch that doesn't exist or has no commits for that path.
	// Or it could be a 422 if the ref is malformed, or 404 if repo/owner is wrong.
	// For a non-existent branch, an empty array is a common valid JSON response.
	// The source resolver should interpret this as "commit not found".
	githubAPIResponseForDep_NotFound := `[]` // Simulates branch not found / no commits for path on branch

	// Raw download path - should NOT be called
	rawDownloadPathDep := fmt.Sprintf("/testowner/testrepo/some_sha_never_reached/%s", depPath)

	pathResps := map[string]struct {
		Body string
		Code int
	}{
		// This API call will "succeed" with an empty list, indicating no commit found for the ref.
		githubAPIPathForDep: {Body: githubAPIResponseForDep_NotFound, Code: http.StatusOK},
		// This should not be called
		rawDownloadPathDep: {Body: "SHOULD NOT BE DOWNLOADED", Code: http.StatusOK},
	}
	mockServer := startMockHTTPServer(t, pathResps)

	originalGHAPIBaseURL := source.GithubAPIBaseURL
	source.GithubAPIBaseURL = mockServer.URL
	defer func() { source.GithubAPIBaseURL = originalGHAPIBaseURL }()

	// --- Run Command ---
	// We can run for all, or specifically for depName. The error should propagate.
	err := runInstallCommand(t, tempDir, depName)
	require.Error(t, err, "almd install command should have failed due to source resolution error")
	// Example: assert.Contains(t, err.Error(), "failed to resolve source")
	// Example: assert.Contains(t, err.Error(), depName) // Error message should mention the problematic dependency

	// --- Assertions ---
	// 1. Verify depBadBranch file is NOT created
	depFilePath := filepath.Join(tempDir, depPath)
	_, statErr := os.Stat(depFilePath)
	assert.True(t, os.IsNotExist(statErr), "depBadBranch file should not have been created")

	// 2. Verify almd-lock.toml is UNCHANGED (or remains in its initial state)
	lockFilePath := filepath.Join(tempDir, lockfile.LockfileName)
	currentLockCfg := readAlmdLockToml(t, lockFilePath) // Read current
	originalLockCfg := lockfile.Lockfile{}              // For comparison
	errUnmarshal := toml.Unmarshal([]byte(initialLockfile), &originalLockCfg)
	require.NoError(t, errUnmarshal, "Failed to unmarshal original lockfile content for comparison")
	assert.Equal(t, originalLockCfg, currentLockCfg, "almd-lock.toml should be unchanged after source resolution error")

	// 3. Verify project.toml remains unchanged
	projTomlPath := filepath.Join(tempDir, config.ProjectTomlName)
	currentProjCfg := readProjectToml(t, projTomlPath)
	originalProjCfg := project.Project{}
	errUnmarshalProj := toml.Unmarshal([]byte(initialProjectToml), &originalProjCfg)
	require.NoError(t, errUnmarshalProj, "Failed to unmarshal original project.toml content for comparison")
	assert.Equal(t, originalProjCfg, currentProjCfg, "project.toml should be unchanged")
}

// Task 7.2.10: Test `almd install` - `project.toml` not found
func TestInstallCommand_ProjectTomlNotFound(t *testing.T) {
	// Setup: Create a temp directory but do NOT create project.toml
	tempDir := setupInstallTestEnvironment(t, "", "", nil) // Empty string for projectTomlContent

	// --- Run Command ---
	// Expect an error because project.toml is missing
	err := runInstallCommand(t, tempDir)

	// --- Assertions ---
	// 1. Verify command returns an error
	require.Error(t, err, "almd install should return an error when project.toml is not found")

	// 2. Verify the error message indicates project.toml was not found
	//    The exact message depends on how internal/core/config.LoadProjectToml and the install command handle this.
	//    Common error messages include "no such file or directory" or a custom "project.toml not found".
	//    Let's check for a substring that is likely to be present.
	//    Based on typical os.ReadFile errors or custom errors from config loading.
	assert.Contains(t, err.Error(), config.ProjectTomlName, "Error message should mention project.toml")
	assert.Contains(t, err.Error(), "not found in the current directory", "Error message should indicate file not found in current directory")
}
