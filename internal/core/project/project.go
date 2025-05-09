package project

// Project represents the overall structure of the project.toml file.
type Project struct {
	Package      *PackageInfo          `toml:"package"`
	Scripts      map[string]string     `toml:"scripts,omitempty"`
	Dependencies map[string]Dependency `toml:"dependencies,omitempty"`
}

// PackageInfo holds metadata for the project.
type PackageInfo struct {
	Name        string `toml:"name"`
	Version     string `toml:"version"`
	License     string `toml:"license,omitempty"`
	Description string `toml:"description,omitempty"`
}

// Dependency represents a single dependency in the project.toml file.
type Dependency struct {
	Source string `toml:"source"`
	Path   string `toml:"path"`
}

// LockFile represents the structure of the almd-lock.toml file.
type LockFile struct {
	APIVersion string                       `toml:"api_version"`
	Package    map[string]LockPackageDetail `toml:"package"`
}

// LockPackageDetail represents a single package entry in the almd-lock.toml file.
type LockPackageDetail struct {
	Source string `toml:"source"` // The exact raw download URL
	Path   string `toml:"path"`   // Relative path to the downloaded file
	Hash   string `toml:"hash"`   // Integrity hash (e.g., "sha256:<hash>" or "commit:<hash>")
}

// NewProject creates and returns a new Project instance with initialized maps.
func NewProject() *Project {
	return &Project{
		Package:      &PackageInfo{}, // Initialize PackageInfo as well
		Scripts:      make(map[string]string),
		Dependencies: make(map[string]Dependency),
	}
}
