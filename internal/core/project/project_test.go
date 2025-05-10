// Package project_test contains tests for the project package.
package project_test

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/nightconcept/almandine/internal/core/project"
)

func TestNewProject(t *testing.T) {
	t.Parallel()
	p := project.NewProject()

	assert.NotNil(t, p, "NewProject should return a non-nil Project instance")
	assert.NotNil(t, p.Package, "Project.Package should be initialized")
	assert.NotNil(t, p.Scripts, "Project.Scripts map should be initialized")
	assert.Empty(t, p.Scripts, "Project.Scripts map should be empty initially")
	assert.NotNil(t, p.Dependencies, "Project.Dependencies map should be initialized")
	assert.Empty(t, p.Dependencies, "Project.Dependencies map should be empty initially")

	assert.Equal(t, "", p.Package.Name, "Package.Name should be empty initially")
	assert.Equal(t, "", p.Package.Version, "Package.Version should be empty initially")
	assert.Equal(t, "", p.Package.License, "Package.License should be empty initially")
	assert.Equal(t, "", p.Package.Description, "Package.Description should be empty initially")
}
