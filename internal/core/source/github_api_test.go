// Package source_test contains tests for the source package, specifically GitHub API interactions.
package source_test

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/nightconcept/almandine/internal/core/source"
)

var githubAPITestMutex sync.Mutex // Mutex to serialize tests modifying global source state

func TestGetLatestCommitSHAForFile_Success(t *testing.T) {
	githubAPITestMutex.Lock()
	defer githubAPITestMutex.Unlock()

	expectedSHA := "abcdef1234567890"
	mockResponse := []source.GitHubCommitInfo{
		{SHA: expectedSHA},
		{SHA: "oldersha789"},
	}
	responseBody, err := json.Marshal(mockResponse)
	require.NoError(t, err)

	_, cleanup := setupSourceTest(t, func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/repos/owner/repo/commits", r.URL.Path, "Request path mismatch")
		assert.Equal(t, "path/to/file.txt", r.URL.Query().Get("path"), "Query param 'path' mismatch")
		assert.Equal(t, "main", r.URL.Query().Get("sha"), "Query param 'sha' mismatch")
		assert.Equal(t, "1", r.URL.Query().Get("per_page"), "Query param 'per_page' mismatch")
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(responseBody)
	})
	defer cleanup()

	sha, err := source.GetLatestCommitSHAForFile("owner", "repo", "path/to/file.txt", "main")
	require.NoError(t, err)
	assert.Equal(t, expectedSHA, sha)
}

func TestGetLatestCommitSHAForFile_EmptyResponse(t *testing.T) {
	githubAPITestMutex.Lock()
	defer githubAPITestMutex.Unlock()

	mockResponse := []source.GitHubCommitInfo{}
	responseBody, err := json.Marshal(mockResponse)
	require.NoError(t, err)

	_, cleanup := setupSourceTest(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(responseBody)
	})
	defer cleanup()

	_, err = source.GetLatestCommitSHAForFile("owner", "repo", "nonexistent/file.txt", "main")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "no commits found for path")
}

func TestGetLatestCommitSHAForFile_GitHubAPIError(t *testing.T) {
	githubAPITestMutex.Lock()
	defer githubAPITestMutex.Unlock()

	_, cleanup := setupSourceTest(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		_, _ = w.Write([]byte(`{"message": "Not Found"}`))
	})
	defer cleanup()

	_, err := source.GetLatestCommitSHAForFile("owner", "repo", "file.txt", "main")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "GitHub API request failed with status 404 Not Found")
}

func TestGetLatestCommitSHAForFile_MalformedJSONResponse(t *testing.T) {
	githubAPITestMutex.Lock()
	defer githubAPITestMutex.Unlock()

	_, cleanup := setupSourceTest(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`this is not valid json`))
	})
	defer cleanup()

	_, err := source.GetLatestCommitSHAForFile("owner", "repo", "file.txt", "main")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "failed to unmarshal GitHub API response")
}

func TestGetLatestCommitSHAForFile_NetworkError(t *testing.T) {
	githubAPITestMutex.Lock()
	defer githubAPITestMutex.Unlock()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hj, ok := w.(http.Hijacker)
		if !ok {
			http.Error(w, "webserver doesn't support hijacking", http.StatusInternalServerError)
			return
		}
		conn, _, err := hj.Hijack()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		_ = conn.Close()
	}))
	// No defer server.Close() here as we close it within the test logic for this specific case.

	source.GithubAPIBaseURLMutex.Lock()
	originalAPIBaseURL := source.GithubAPIBaseURL
	source.GithubAPIBaseURL = server.URL
	source.GithubAPIBaseURLMutex.Unlock()
	source.SetTestModeBypassHostValidation(true) // This function handles its own locking

	server.Close()

	_, err := source.GetLatestCommitSHAForFile("owner", "repo", "file.txt", "main")

	source.GithubAPIBaseURLMutex.Lock()
	source.GithubAPIBaseURL = originalAPIBaseURL
	source.GithubAPIBaseURLMutex.Unlock()
	source.SetTestModeBypassHostValidation(false) // This function handles its own locking

	require.Error(t, err)
	assert.Contains(t, err.Error(), "failed to call GitHub API")
}

// MockGitHubCommit is a helper to create GitHubCommitInfo for tests
func MockGitHubCommit(sha string, date time.Time) source.GitHubCommitInfo {
	return source.GitHubCommitInfo{
		SHA: sha,
		Commit: struct {
			Committer struct {
				Date time.Time `json:"date"`
			} `json:"committer"`
		}{
			Committer: struct {
				Date time.Time `json:"date"`
			}{
				Date: date,
			},
		},
	}
}

func TestGetLatestCommitSHAForFile_UsesCorrectURLParameters(t *testing.T) {
	githubAPITestMutex.Lock()
	defer githubAPITestMutex.Unlock()

	owner, repo, pathInRepo, ref := "test-owner", "test-repo", "src/main.go", "develop"
	expectedSHA := "commitsha123"

	mockResponse := []source.GitHubCommitInfo{MockGitHubCommit(expectedSHA, time.Now())}
	responseBody, _ := json.Marshal(mockResponse)

	_, cleanup := setupSourceTest(t, func(w http.ResponseWriter, r *http.Request) {
		expectedPath := fmt.Sprintf("/repos/%s/%s/commits", owner, repo)
		assert.Equal(t, expectedPath, r.URL.Path)
		assert.Equal(t, pathInRepo, r.URL.Query().Get("path"))
		assert.Equal(t, ref, r.URL.Query().Get("sha"))
		assert.Equal(t, "1", r.URL.Query().Get("per_page"))
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(responseBody)
	})
	defer cleanup()

	sha, err := source.GetLatestCommitSHAForFile(owner, repo, pathInRepo, ref)
	require.NoError(t, err)
	assert.Equal(t, expectedSHA, sha)
}
