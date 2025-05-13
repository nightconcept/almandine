// Package remove handles project dependency removal operations
package remove

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/fatih/color"
	"github.com/nightconcept/almandine/internal/core/config"
	"github.com/nightconcept/almandine/internal/core/lockfile"
	"github.com/nightconcept/almandine/internal/core/project"
	"github.com/nightconcept/almandine/internal/core/source"
	"github.com/urfave/cli/v2"
)

func isDirEmpty(path string) (bool, error) {
	entries, err := os.ReadDir(path)
	if err != nil {
		return false, fmt.Errorf("failed to read directory %s: %w", path, err)
	}
	return len(entries) == 0, nil
}

func loadProjectConfigAndValidate(depName string) (proj *project.Project, depDetails project.Dependency, err error) {
	proj, err = config.LoadProjectToml(".")
	if err != nil {
		return nil, project.Dependency{}, fmt.Errorf("failed to load %s: %w", config.ProjectTomlName, err)
	}

	if len(proj.Dependencies) == 0 {
		return proj, project.Dependency{}, fmt.Errorf("no dependencies found in %s", config.ProjectTomlName)
	}

	depDetails, ok := proj.Dependencies[depName]
	if !ok {
		return proj, project.Dependency{}, fmt.Errorf("dependency '%s' not found in %s", depName, config.ProjectTomlName)
	}
	return proj, depDetails, nil
}

func updateManifest(proj *project.Project, depName string) error {
	delete(proj.Dependencies, depName)
	if err := config.WriteProjectToml(".", proj); err != nil {
		return fmt.Errorf("failed to update %s: %w", config.ProjectTomlName, err)
	}
	return nil
}

func deleteDependencyFileAndCleanup(errWriter io.Writer, dependencyPath string) (fileDeleted bool) {
	if err := os.Remove(dependencyPath); err != nil {
		if !os.IsNotExist(err) {
			_, _ = fmt.Fprintf(errWriter, "Warning: Failed to delete dependency file '%s': %v. Manifest updated.\n", dependencyPath, err)
		}
		return false
	}

	fileDeleted = true
	currentDir := filepath.Dir(dependencyPath)
	projectRootAbs, errAbs := filepath.Abs(".")
	if errAbs != nil {
		_, _ = fmt.Fprintf(errWriter, "Warning: Could not determine project root absolute path: %v. Skipping directory cleanup.\n", errAbs)
		return fileDeleted
	}

	// Recursively clean up empty parent directories up to project root
	for {
		absCurrentDir, errLoopAbs := filepath.Abs(currentDir)
		if errLoopAbs != nil {
			_, _ = fmt.Fprintf(errWriter, "Warning: Could not get absolute path for '%s': %v. Stopping directory cleanup.\n", currentDir, errLoopAbs)
			break
		}
		// Stop if currentDir is project root, or if its parent is itself (e.g. "/" or "C:\"), or if it's "."
		if absCurrentDir == projectRootAbs || filepath.Dir(absCurrentDir) == absCurrentDir || currentDir == "." || currentDir == "" {
			break
		}
		empty, errEmpty := isDirEmpty(currentDir)
		if errEmpty != nil {
			_, _ = fmt.Fprintf(errWriter, "Warning: Could not check if directory '%s' is empty: %v. Stopping directory cleanup.\n", currentDir, errEmpty)
			break
		}
		if !empty {
			break
		}
		if errRemoveDir := os.Remove(currentDir); errRemoveDir != nil {
			_, _ = fmt.Fprintf(errWriter, "Warning: Failed to remove empty directory '%s': %v. Stopping directory cleanup.\n", currentDir, errRemoveDir)
			break
		}
		currentDir = filepath.Dir(currentDir)
	}
	return fileDeleted
}

func updateLockfile(errWriter io.Writer, depName string) (lockfileUpdated bool, lockfileLoadErr error) {
	lf, err := lockfile.Load(".")
	if err != nil {
		_, _ = fmt.Fprintf(errWriter, "Warning: Failed to load %s: %v. Manifest and file processed.\n", lockfile.LockfileName, err)
		return false, err
	}

	if lf.Package != nil {
		if _, depInLock := lf.Package[depName]; depInLock {
			delete(lf.Package, depName)
			if errSaveLock := lockfile.Save(".", lf); errSaveLock != nil {
				_, _ = fmt.Fprintf(errWriter, "Warning: Failed to update %s: %v. Manifest and file processed.\n", lockfile.LockfileName, errSaveLock)
				return false, err // Return original load error for note consistency
			}
			return true, nil
		}
	}
	return false, nil // Dependency not in lockfile, or lockfile was empty/nil package map
}

func printSummaryAndNotes(
	c *cli.Context,
	depName, dependencySource string,
	fileDeleted, lockfileUpdated bool,
	lockfileLoadErr error,
	dependencyPath string,
	startTime time.Time,
	errWriter io.Writer,
) {
	fmt.Println("Progress: resolved 0, reused 0, downloaded 0, removed 1, done")
	fmt.Println()
	_, _ = color.New(color.FgWhite, color.Bold).Println("dependencies:")

	versionStr := "unknown"
	parsedInfo, parseErr := source.ParseSourceURL(dependencySource)
	if parseErr == nil && parsedInfo != nil && parsedInfo.Ref != "" && !strings.HasPrefix(parsedInfo.Ref, "error:") {
		versionStr = parsedInfo.Ref
	}

	_, _ = color.New(color.FgRed).Printf("- %s %s\n", depName, versionStr)
	fmt.Println()
	duration := time.Since(startTime)
	fmt.Printf("Done in %.1fs\n", duration.Seconds())

	if !fileDeleted {
		_, _ = fmt.Fprintf(errWriter, "Note: Dependency file '%s' was not deleted (either not found or error during deletion).\n", dependencyPath)
	}
	// Note: lockfileLoadErr being non-nil implies lockfile was not loaded, hence not updated.
	// If lockfileLoadErr is nil, but lockfileUpdated is false, it means dep was not in lockfile or save failed (which updateLockfile warns about).
	if lockfileLoadErr != nil {
		// This case is already handled by updateLockfile's warning, but we ensure the note reflects it.
		_, _ = fmt.Fprintf(errWriter, "Note: Lockfile '%s' could not be loaded to remove '%s'.\n", lockfile.LockfileName, depName)
	} else if !lockfileUpdated {
		_, _ = fmt.Fprintf(errWriter, "Note: Lockfile '%s' was not updated for '%s' (either dependency not found in lockfile or error during save).\n", lockfile.LockfileName, depName)
	}
}

// RemoveCmd handles the 'remove' subcommand
func RemoveCmd() *cli.Command {
	return &cli.Command{
		Name:      "remove",
		Aliases:   []string{"rm", "uninstall", "un"},
		Usage:     "Remove a dependency from the project",
		ArgsUsage: "DEPENDENCY",
		Action: func(c *cli.Context) error {
			startTime := time.Now()

			var errWriter io.Writer = os.Stderr
			if c.App != nil && c.App.ErrWriter != nil {
				errWriter = c.App.ErrWriter
			}

			if !c.Args().Present() {
				return cli.Exit("Error: Dependency name argument is required.", 1)
			}
			depName := c.Args().First()

			proj, depDetails, err := loadProjectConfigAndValidate(depName)
			if err != nil {
				return cli.Exit(fmt.Sprintf("Error: %v", err), 1)
			}
			dependencyPath := depDetails.Path
			dependencySource := depDetails.Source

			if err := updateManifest(proj, depName); err != nil {
				return cli.Exit(fmt.Sprintf("Error: %v", err), 1)
			}

			fileDeleted := deleteDependencyFileAndCleanup(errWriter, dependencyPath)
			lockfileUpdated, lockfileLoadErr := updateLockfile(errWriter, depName)

			printSummaryAndNotes(c, depName, dependencySource, fileDeleted, lockfileUpdated, lockfileLoadErr, dependencyPath, startTime, errWriter)

			return nil
		},
	}
}
