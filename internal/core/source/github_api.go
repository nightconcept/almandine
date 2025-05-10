package source

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sync"
	"time"
)

// GithubAPIBaseURL allows overriding for tests. It is an exported variable.
var GithubAPIBaseURL = "https://api.github.com"
var GithubAPIBaseURLMutex sync.Mutex // Mutex for GithubAPIBaseURL (Exported)

// GitHubCommitInfo minimal structure to parse the commit SHA.
type GitHubCommitInfo struct {
	SHA    string `json:"sha"`
	Commit struct {
		Committer struct {
			Date time.Time `json:"date"`
		} `json:"committer"`
	} `json:"commit"`
	// We only need the SHA, but including date for potential future use/sorting.
}

// GetLatestCommitSHAForFile fetches the latest commit SHA for a specific file on a given branch/ref from GitHub.
// owner: repository owner
// repo: repository name
// pathInRepo: path to the file within the repository
// ref: branch name, tag name, or commit SHA
func GetLatestCommitSHAForFile(owner, repo, pathInRepo, ref string) (string, error) {
	// See: https://docs.github.com/en/rest/commits/commits#list-commits
	// We ask for commits for a specific file on a specific branch/ref. The first result is the latest.
	GithubAPIBaseURLMutex.Lock()
	currentGithubAPIBaseURL := GithubAPIBaseURL
	GithubAPIBaseURLMutex.Unlock()
	apiURL := fmt.Sprintf("%s/repos/%s/%s/commits?path=%s&sha=%s&per_page=1", currentGithubAPIBaseURL, owner, repo, pathInRepo, ref)

	httpClient := &http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequest("GET", apiURL, nil)
	if err != nil {
		return "", fmt.Errorf("failed to create request to GitHub API: %w", err)
	}
	// GitHub API recommends setting an Accept header.
	req.Header.Set("Accept", "application/vnd.github.v3+json")
	// TODO: Consider adding a User-Agent header (e.g., "almandine-cli") for more robust GitHub API requests.

	resp, err := httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to call GitHub API (%s): %w", apiURL, err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("GitHub API request failed with status %s (%s): %s", resp.Status, apiURL, string(bodyBytes))
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response body from GitHub API (%s): %w", apiURL, err)
	}

	var commits []GitHubCommitInfo
	if err := json.Unmarshal(body, &commits); err != nil {
		return "", fmt.Errorf("failed to unmarshal GitHub API response (%s): %w. Body: %s", apiURL, err, string(body))
	}

	if len(commits) == 0 {
		// This can happen if the path is incorrect for the given ref, or the ref itself doesn't exist.
		// Or if the ref *is* a commit SHA, and the file wasn't modified in that specific commit (the API returns history).
		// If ref is already a SHA, we should ideally use it directly. This function assumes ref might be a branch.
		// If no commits are returned for a file on a branch, it implies the file might not exist on that branch or path is wrong.
		return "", fmt.Errorf("no commits found for path '%s' at ref '%s' in repo '%s/%s'. The file might not exist at this path/ref, or the ref might be a specific commit SHA where this file was not modified", pathInRepo, ref, owner, repo)
	}

	return commits[0].SHA, nil
}
