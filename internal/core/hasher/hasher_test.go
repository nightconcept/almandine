// Package hasher_test contains tests for the hasher package.
package hasher_test

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/nightconcept/almandine/internal/core/hasher"
)

func TestCalculateSHA256_KnownString(t *testing.T) {
	t.Parallel()
	content := []byte("Hello, Almandine!")
	// SHA256 hash of "Hello, Almandine!" is 94115f449b029dd58934f8f40187377d739c16b9e26231fb8478b57774674d27
	expectedHash := "sha256:94115f449b029dd58934f8f40187377d739c16b9e26231fb8478b57774674d27"

	actualHash, err := hasher.CalculateSHA256(content)
	require.NoError(t, err, "CalculateSHA256 returned an unexpected error")
	assert.Equal(t, expectedHash, actualHash, "Calculated hash does not match expected hash")
}

func TestCalculateSHA256_EmptyContent(t *testing.T) {
	t.Parallel()
	content := []byte{}
	// SHA256 hash of an empty string is e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
	expectedHash := "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

	actualHash, err := hasher.CalculateSHA256(content)
	require.NoError(t, err, "CalculateSHA256 returned an unexpected error for empty content")
	assert.Equal(t, expectedHash, actualHash, "Calculated hash for empty content does not match expected hash")
}

func TestCalculateSHA256_DifferentContent(t *testing.T) {
	t.Parallel()
	content1 := []byte("almandine-rocks")
	// SHA256 of "almandine-rocks" is 8a6efd3f01b4243416969a80dba1c15964ecf9417d857e0db41e2816d646014a
	expectedHash1 := "sha256:8a6efd3f01b4243416969a80dba1c15964ecf9417d857e0db41e2816d646014a"

	content2 := []byte("almandine-rules")
	// SHA256 of "almandine-rules" is 651b85f3ae43ecbd22f0fb8d3e80abe5abab27a96caff09c3fcca5d9155087b8
	expectedHash2 := "sha256:651b85f3ae43ecbd22f0fb8d3e80abe5abab27a96caff09c3fcca5d9155087b8"

	actualHash1, err1 := hasher.CalculateSHA256(content1)
	require.NoError(t, err1)
	assert.Equal(t, expectedHash1, actualHash1)

	actualHash2, err2 := hasher.CalculateSHA256(content2)
	require.NoError(t, err2)
	assert.Equal(t, expectedHash2, actualHash2)

	assert.NotEqual(t, actualHash1, actualHash2, "Hashes for different content should not be the same")
}
