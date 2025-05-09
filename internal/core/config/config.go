package config

import (
	"bytes"
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"
	"github.com/nightconcept/almandine/internal/core/project" // Corrected module path
)

const ProjectTomlName = "project.toml"
const LockfileName = "almd-lock.toml"

// LoadProjectToml reads the project.toml file from the given dirPath and unmarshals it.
func LoadProjectToml(dirPath string) (*project.Project, error) {
	fullPath := filepath.Join(dirPath, ProjectTomlName)
	data, err := os.ReadFile(fullPath)
	if err != nil {
		return nil, err
	}

	var proj project.Project
	if err := toml.Unmarshal(data, &proj); err != nil {
		return nil, err
	}
	return &proj, nil
}

// WriteProjectToml marshals the Project data and writes it to the specified dirPath.
// It will overwrite the file if it already exists.
func WriteProjectToml(dirPath string, data *project.Project) error {
	buf := new(bytes.Buffer)
	if err := toml.NewEncoder(buf).Encode(data); err != nil {
		return err
	}

	// Write the TOML content to the file, overwriting if it exists.
	// Create the file if it doesn't exist, with default permissions (0666 before umask).
	// O_TRUNC ensures that if the file exists, its content is truncated.
	fullPath := filepath.Join(dirPath, ProjectTomlName)
	file, err := os.OpenFile(fullPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0644)
	if err != nil {
		return err
	}
	defer func() { _ = file.Close() }()

	_, err = file.Write(buf.Bytes())
	return err
}
