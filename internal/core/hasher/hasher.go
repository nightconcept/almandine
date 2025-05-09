package hasher

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
)

// CalculateSHA256 computes the SHA256 hash of the given content
// and returns it in the format "sha256:<hex_hash>".
func CalculateSHA256(content []byte) (string, error) {
	hasher := sha256.New()
	_, err := hasher.Write(content)
	if err != nil {
		return "", fmt.Errorf("failed to write content to hasher: %w", err)
	}
	hashBytes := hasher.Sum(nil)
	hashString := hex.EncodeToString(hashBytes)
	return fmt.Sprintf("sha256:%s", hashString), nil
}
