package source

import (
	"fmt"
	"net/url"
	"strings"
	"sync"
)

// testModeBypassHostValidation is an internal flag for testing to bypass hostname checks.
// WARNING: This should only be set to true in test environments.
var testModeBypassHostValidation = false
var TestModeBypassHostValidationMutex sync.Mutex // Mutex for testModeBypassHostValidation (Exported)

// SetTestModeBypassHostValidation enables or disables the hostname validation bypass for testing.
// This function is intended to be called only from test packages.
func SetTestModeBypassHostValidation(enable bool) {
	TestModeBypassHostValidationMutex.Lock()
	testModeBypassHostValidation = enable
	TestModeBypassHostValidationMutex.Unlock()
}

// ParsedSourceInfo holds the details extracted from a source URL.
type ParsedSourceInfo struct {
	RawURL            string
	CanonicalURL      string
	Ref               string
	Provider          string
	Owner             string
	Repo              string
	PathInRepo        string
	SuggestedFilename string
}

// ParseSourceURL analyzes the input source URL string and returns structured information.
// It currently prioritizes GitHub URLs.
func ParseSourceURL(sourceURL string) (*ParsedSourceInfo, error) {
	if strings.HasPrefix(sourceURL, "github:") {
		return parseGitHubShorthandURL(sourceURL)
	}

	u, err := url.Parse(sourceURL)
	if err != nil {
		return nil, fmt.Errorf("failed to parse source URL '%s': %w", sourceURL, err)
	}

	TestModeBypassHostValidationMutex.Lock()
	currentTestModeBypass := testModeBypassHostValidation
	TestModeBypassHostValidationMutex.Unlock()

	if currentTestModeBypass {
		// If test mode bypass is active, attempt to parse it as a test mode URL.
		// This function will error if the path doesn't match the expected test structure.
		return parseTestModeURL(u)
	}

	// Standard URL parsing
	hostname := strings.ToLower(u.Hostname())
	switch hostname {
	case "raw.githubusercontent.com":
		return parseRawGitHubUserContentURL(u)
	case "github.com":
		return parseGitHubFullURL(u)
	default:
		return nil, fmt.Errorf("unsupported source URL host: %s. Only GitHub URLs are currently supported", u.Hostname())
	}
}

// parseGitHubShorthandURL handles URLs like "github:owner/repo/path/to/file@ref"
func parseGitHubShorthandURL(sourceURL string) (*ParsedSourceInfo, error) {
	content := strings.TrimPrefix(sourceURL, "github:")

	lastAt := strings.LastIndex(content, "@")
	if lastAt == -1 {
		return nil, fmt.Errorf("invalid github shorthand source '%s': missing @ref (e.g., @main or @commitsha)", sourceURL)
	}
	if lastAt == len(content)-1 {
		return nil, fmt.Errorf("invalid github shorthand source '%s': ref part is empty after @", sourceURL)
	}

	repoAndPathPart := content[:lastAt]
	ref := content[lastAt+1:]

	pathComponents := strings.Split(repoAndPathPart, "/")
	if len(pathComponents) < 3 {
		return nil, fmt.Errorf("invalid github shorthand source '%s': expected format owner/repo/path/to/file, got '%s'", sourceURL, repoAndPathPart)
	}

	owner := pathComponents[0]
	repo := pathComponents[1]
	pathInRepo := strings.Join(pathComponents[2:], "/")
	suggestedFilename := pathComponents[len(pathComponents)-1]

	if owner == "" || repo == "" || pathInRepo == "" || suggestedFilename == "" {
		return nil, fmt.Errorf("invalid github shorthand source '%s': owner, repo, or path/filename cannot be empty", sourceURL)
	}

	var rawURL string
	TestModeBypassHostValidationMutex.Lock()
	currentTestModeBypassLocal := testModeBypassHostValidation // Use a local var to avoid holding lock too long
	TestModeBypassHostValidationMutex.Unlock()

	if currentTestModeBypassLocal {
		GithubAPIBaseURLMutex.Lock()
		currentGithubAPIBaseURL := GithubAPIBaseURL
		GithubAPIBaseURLMutex.Unlock()
		rawURL = fmt.Sprintf("%s/%s/%s/%s/%s", currentGithubAPIBaseURL, owner, repo, ref, pathInRepo)
	} else {
		rawURL = fmt.Sprintf("https://raw.githubusercontent.com/%s/%s/%s/%s", owner, repo, ref, pathInRepo)
	}

	return &ParsedSourceInfo{
		RawURL:            rawURL,
		CanonicalURL:      sourceURL, // For shorthand, the sourceURL is the canonical form
		Ref:               ref,
		Provider:          "github",
		Owner:             owner,
		Repo:              repo,
		PathInRepo:        pathInRepo,
		SuggestedFilename: suggestedFilename,
	}, nil
}

// parseTestModeURL handles generic URLs when testModeBypassHostValidation is true,
// attempting to parse them with a GitHub-like raw content path structure.
func parseTestModeURL(u *url.URL) (*ParsedSourceInfo, error) {
	// Path structure expected: /<owner>/<repo>/<ref>/<path_to_file...>
	pathParts := strings.Split(strings.Trim(u.Path, "/"), "/")
	if len(pathParts) < 4 {
		return nil, fmt.Errorf("test mode URL path '%s' not in expected format /<owner>/<repo>/<ref>/<file...> PpathParts was: %v", u.Path, pathParts)
	}

	owner := pathParts[0]
	repo := pathParts[1]
	ref := pathParts[2]
	filePathInRepo := strings.Join(pathParts[3:], "/")
	filename := pathParts[len(pathParts)-1]

	if filename == "" && filePathInRepo == "" {
		return nil, fmt.Errorf("test mode URL path '%s' seems to point to a directory, not a file", u.Path)
	}
	if filename == "" && len(pathParts) == 4 { // e.g. /owner/repo/ref/file
		filename = pathParts[3]
	}

	return &ParsedSourceInfo{
		RawURL:            u.String(), // The original URL is the raw URL in this test mode context
		CanonicalURL:      fmt.Sprintf("github:%s/%s/%s@%s", owner, repo, filePathInRepo, ref),
		Ref:               ref,
		Provider:          "github", // Assumed GitHub provider in test mode parsing
		Owner:             owner,
		Repo:              repo,
		PathInRepo:        filePathInRepo,
		SuggestedFilename: filename,
	}, nil
}

// parseRawGitHubUserContentURL handles URLs from "raw.githubusercontent.com".
func parseRawGitHubUserContentURL(u *url.URL) (*ParsedSourceInfo, error) {
	pathParts := strings.Split(strings.Trim(u.Path, "/"), "/")
	if len(pathParts) < 4 {
		return nil, fmt.Errorf("invalid GitHub raw content URL path: %s. Expected format: /<owner>/<repo>/<ref>/<path_to_file>", u.Path)
	}
	owner := pathParts[0]
	repo := pathParts[1]
	ref := pathParts[2]
	filePathInRepo := strings.Join(pathParts[3:], "/")
	filename := pathParts[len(pathParts)-1]

	if owner == "" || repo == "" || ref == "" || filePathInRepo == "" || filename == "" {
		return nil, fmt.Errorf("invalid GitHub raw content URL '%s': one or more components (owner, repo, ref, path, filename) are empty", u.String())
	}

	canonicalURL := fmt.Sprintf("github:%s/%s/%s@%s", owner, repo, filePathInRepo, ref)
	return &ParsedSourceInfo{
		RawURL:            u.String(),
		CanonicalURL:      canonicalURL,
		Ref:               ref,
		Provider:          "github",
		Owner:             owner,
		Repo:              repo,
		PathInRepo:        filePathInRepo,
		SuggestedFilename: filename,
	}, nil
}

// parseGitHubFullURL handles standard "github.com" URLs (blob, tree, raw, or path with @ref).
func parseGitHubFullURL(u *url.URL) (*ParsedSourceInfo, error) {
	pathParts := strings.Split(strings.Trim(u.Path, "/"), "/")
	if len(pathParts) < 2 {
		return nil, fmt.Errorf("invalid GitHub URL path: %s. Expected at least /<owner>/<repo>", u.Path)
	}

	owner := pathParts[0]
	repo := pathParts[1]
	var ref, filePathInRepo, rawURL, filename string
	var err error

	if len(pathParts) >= 4 && (pathParts[2] == "blob" || pathParts[2] == "tree" || pathParts[2] == "raw") {
		ref, filePathInRepo, filename, rawURL, err = parseGitHubURLWithType(u, owner, repo, pathParts)
		if err != nil {
			return nil, err
		}
	} else {
		ref, filePathInRepo, filename, rawURL, err = parseGitHubURLWithAtRef(u, owner, repo, pathParts)
		if err != nil {
			return nil, err
		}
	}

	// Common validations after attempting to parse
	if owner == "" {
		return nil, fmt.Errorf("owner could not be determined from URL: %s", u.String())
	}
	if repo == "" {
		return nil, fmt.Errorf("repository could not be determined from URL: %s", u.String())
	}
	if filePathInRepo == "" {
		return nil, fmt.Errorf("file path in repository could not be determined from URL: %s", u.String())
	}
	if ref == "" {
		return nil, fmt.Errorf("ref (branch, tag, commit) could not be determined from URL: %s. Please specify it", u.String())
	}
	if filename == "" {
		return nil, fmt.Errorf("filename could not be determined from URL: %s", u.String())
	}
	if rawURL == "" { // Should be set by helpers
		return nil, fmt.Errorf("raw download URL could not be constructed for URL: %s", u.String())
	}

	canonicalURL := fmt.Sprintf("github:%s/%s/%s@%s", owner, repo, filePathInRepo, ref)

	return &ParsedSourceInfo{
		RawURL:            rawURL,
		CanonicalURL:      canonicalURL,
		Ref:               ref,
		Provider:          "github",
		Owner:             owner,
		Repo:              repo,
		PathInRepo:        filePathInRepo,
		SuggestedFilename: filename,
	}, nil
}

// parseGitHubURLWithType handles URLs like /<owner>/<repo>/<type>/<ref>/<path_to_file>
func parseGitHubURLWithType(u *url.URL, owner, repo string, pathParts []string) (ref, filePathInRepo, filename, rawURL string, err error) {
	if len(pathParts) < 5 {
		err = fmt.Errorf("incomplete GitHub URL path: %s. Expected /<owner>/<repo>/<type>/<ref>/<path_to_file>", u.Path)
		return
	}
	refType := pathParts[2]
	ref = pathParts[3]
	filePathInRepo = strings.Join(pathParts[4:], "/")
	filename = pathParts[len(pathParts)-1]

	if refType == "tree" {
		err = fmt.Errorf("direct links to GitHub trees are not supported for adding single files: %s", u.String())
		return
	}
	if owner == "" || repo == "" || ref == "" || filePathInRepo == "" || filename == "" {
		err = fmt.Errorf("invalid GitHub '%s' URL '%s': one or more components (owner, repo, ref, path, filename) are empty", refType, u.String())
		return
	}
	rawURL = fmt.Sprintf("https://raw.githubusercontent.com/%s/%s/%s/%s", owner, repo, ref, filePathInRepo)
	return
}

// parseGitHubURLWithAtRef handles URLs like /<owner>/<repo>/<path_to_file>@<ref>
func parseGitHubURLWithAtRef(u *url.URL, owner, repo string, pathParts []string) (ref, filePathInRepo, filename, rawURL string, err error) {
	if len(pathParts) < 3 { // Need at least owner/repo/fileish@ref
		err = fmt.Errorf("ambiguous GitHub URL path: %s. Expected /owner/repo/path@ref or a full /blob/ or /raw/ URL", u.Path)
		return
	}
	potentialPathWithRef := strings.Join(pathParts[2:], "/")
	atSymbolIndex := strings.LastIndex(potentialPathWithRef, "@")

	if atSymbolIndex != -1 && atSymbolIndex < len(potentialPathWithRef)-1 && atSymbolIndex > 0 {
		filePathInRepo = potentialPathWithRef[:atSymbolIndex]
		ref = potentialPathWithRef[atSymbolIndex+1:]
		pathElements := strings.Split(filePathInRepo, "/")
		if len(pathElements) > 0 {
			filename = pathElements[len(pathElements)-1]
		} else { // Should not happen if atSymbolIndex > 0
			err = fmt.Errorf("could not determine filename from path '%s' in URL '%s'", filePathInRepo, u.String())
			return
		}
	} else {
		err = fmt.Errorf("ambiguous GitHub URL: %s. Specify a branch/tag/commit via '@' (e.g., file.txt@main) or use a full /blob/ or /raw/ URL", u.String())
		return
	}

	if owner == "" || repo == "" || ref == "" || filePathInRepo == "" || filename == "" {
		err = fmt.Errorf("invalid GitHub URL with '@ref' syntax '%s': one or more components (owner, repo, ref, path, filename) are empty", u.String())
		return
	}
	rawURL = fmt.Sprintf("https://raw.githubusercontent.com/%s/%s/%s/%s", owner, repo, ref, filePathInRepo)
	return
}
