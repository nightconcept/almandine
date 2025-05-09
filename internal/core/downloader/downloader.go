// Package downloader provides functionality to download files from URLs.
package downloader

import (
	"fmt"
	"io"
	"net/http"
)

// DownloadFile fetches the content from the given URL.
// It returns the content as a byte slice or an error if the download fails
// or if the HTTP status code is not 200 OK.
func DownloadFile(url string) ([]byte, error) {
	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("failed to perform GET request to %s: %w", url, err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("failed to download from %s: received status code %d", url, resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body from %s: %w", url, err)
	}

	return body, nil
}
