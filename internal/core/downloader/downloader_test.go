// Package downloader_test contains tests for the downloader package.
package downloader_test

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/nightconcept/almandine/internal/core/downloader"
)

func TestDownloadFile_Success(t *testing.T) {
	t.Parallel()
	expectedContent := "Hello, Almandine!"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, err := w.Write([]byte(expectedContent))
		require.NoError(t, err, "Failed to write response in mock server")
	}))
	defer server.Close()

	content, err := downloader.DownloadFile(server.URL)
	require.NoError(t, err, "DownloadFile returned an unexpected error")
	assert.Equal(t, []byte(expectedContent), content, "Downloaded content does not match expected content")
}

func TestDownloadFile_HTTPErrorNotFound(t *testing.T) {
	t.Parallel()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	_, err := downloader.DownloadFile(server.URL)
	require.Error(t, err, "DownloadFile should have returned an error for 404")
	assert.Contains(t, err.Error(), "failed to download from", "Error message mismatch")
	assert.Contains(t, err.Error(), "received status code 404", "Error message mismatch for status code")
}

func TestDownloadFile_HTTPErrorInternalServer(t *testing.T) {
	t.Parallel()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer server.Close()

	_, err := downloader.DownloadFile(server.URL)
	require.Error(t, err, "DownloadFile should have returned an error for 500")
	assert.Contains(t, err.Error(), "failed to download from", "Error message mismatch")
	assert.Contains(t, err.Error(), "received status code 500", "Error message mismatch for status code")
}

func TestDownloadFile_NetworkError_InvalidURL(t *testing.T) {
	t.Parallel()
	invalidURL := "http://invalid-url-that-should-not-exist-for-testing.localdomain"

	_, err := downloader.DownloadFile(invalidURL)
	require.Error(t, err, "DownloadFile should have returned an error for an invalid/unreachable URL")
	assert.Contains(t, err.Error(), fmt.Sprintf("failed to perform GET request to %s", invalidURL), "Error message mismatch for network error")
}

func TestDownloadFile_ReadBodyError(t *testing.T) {
	t.Parallel()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", "100")
		w.WriteHeader(http.StatusOK)
		hj, ok := w.(http.Hijacker)
		if !ok {
			t.Fatal("webserver doesn't support hijacking")
		}
		conn, _, err := hj.Hijack()
		if err != nil {
			t.Fatalf("failed to hijack connection: %v", err)
		}
		_, _ = conn.Write([]byte("HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\npartial data"))
		_ = conn.Close()
	}))
	defer server.Close()

	_, err := downloader.DownloadFile(server.URL)
	require.Error(t, err, "DownloadFile should have returned an error when reading the body fails")
	assert.Contains(t, err.Error(), fmt.Sprintf("failed to read response body from %s", server.URL), "Error message mismatch for read body error")
}
