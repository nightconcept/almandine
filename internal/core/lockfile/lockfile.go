package lockfile

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"
)

const LockfileName = "almd-lock.toml"
const APIVersion = "1"

// PackageEntry represents a single package entry in the lockfile.
// Example:
// [packages."dependency-name"]
//
//	source = "exact raw download URL"
//	path = "relative/path/to/file.ext"
//	hash = "sha256:<hash_value>" or "commit:<commit_hash>"
type PackageEntry struct {
	Source string `toml:"source"`
	Path   string `toml:"path"`
	Hash   string `toml:"hash"`
}

// Lockfile represents the structure of the almd-lock.toml file.
type Lockfile struct {
	ApiVersion string                  `toml:"api_version"`
	Package    map[string]PackageEntry `toml:"package"`
}

// New creates a new Lockfile instance with default values.
func New() *Lockfile {
	return &Lockfile{
		ApiVersion: APIVersion,
		Package:    make(map[string]PackageEntry),
	}
}

// Load loads the lockfile from the given project root path.
// If the lockfile doesn't exist, it returns a new Lockfile instance.
func Load(projectRoot string) (*Lockfile, error) {
	lockfilePath := filepath.Join(projectRoot, LockfileName)
	lf := New()

	if _, err := os.Stat(lockfilePath); os.IsNotExist(err) {
		return lf, nil // Return a new lockfile if it doesn't exist
	} else if err != nil {
		return nil, fmt.Errorf("failed to stat lockfile %s: %w", lockfilePath, err)
	}

	if _, err := toml.DecodeFile(lockfilePath, &lf); err != nil {
		return nil, fmt.Errorf("failed to decode lockfile %s: %w", lockfilePath, err)
	}
	// Ensure API version is present, even if file was empty or had it missing
	if lf.ApiVersion == "" {
		lf.ApiVersion = APIVersion
	}
	// Ensure Packages map is initialized
	if lf.Package == nil {
		lf.Package = make(map[string]PackageEntry)
	}
	return lf, nil
}

// Save saves the lockfile to the given project root path.
func Save(projectRoot string, lf *Lockfile) error {
	lockfilePath := filepath.Join(projectRoot, LockfileName)
	file, err := os.Create(lockfilePath)
	if err != nil {
		return fmt.Errorf("failed to create/truncate lockfile %s: %w", lockfilePath, err)
	}
	defer func() { _ = file.Close() }()

	encoder := toml.NewEncoder(file)
	if err := encoder.Encode(lf); err != nil {
		return fmt.Errorf("failed to encode lockfile %s: %w", lockfilePath, err)
	}
	return nil
}

// AddOrUpdatePackage adds or updates a package entry in the lockfile.
func (lf *Lockfile) AddOrUpdatePackage(name, rawURL, relativePath, integrityHash string) {
	if lf.Package == nil {
		lf.Package = make(map[string]PackageEntry)
	}
	lf.Package[name] = PackageEntry{
		Source: rawURL,
		Path:   relativePath,
		Hash:   integrityHash,
	}
}
