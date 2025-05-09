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
	"github.com/nightconcept/almandine/internal/core/source" // Changed from project to source
	"github.com/urfave/cli/v2"
)

// isDirEmpty checks if a directory is empty.
// It returns true if the directory has no entries, false otherwise.
// An error is returned if the directory cannot be read.
func isDirEmpty(path string) (bool, error) {
	entries, err := os.ReadDir(path)
	if err != nil {
		return false, fmt.Errorf("failed to read directory %s: %w", path, err)
	}
	return len(entries) == 0, nil
}

// RemoveCmd defines the structure for the 'remove' CLI command.
func RemoveCmd() *cli.Command {
	return &cli.Command{
		Name:      "remove",
		Usage:     "Remove a dependency from the project",
		ArgsUsage: "DEPENDENCY",
		Action: func(c *cli.Context) error {
			startTime := time.Now()
			if !c.Args().Present() {
				return fmt.Errorf("dependency name is required")
			}

			depName := c.Args().First()

			// Load project.toml from the current directory
			proj, err := config.LoadProjectToml(".")
			if err != nil {
				return cli.Exit(fmt.Sprintf("Error: Failed to load %s: %v", config.ProjectTomlName, err), 1)
			}

			if len(proj.Dependencies) == 0 {
				return cli.Exit(fmt.Sprintf("Error: No dependencies found in %s.", config.ProjectTomlName), 1)
			}

			dep, ok := proj.Dependencies[depName]
			if !ok {
				return cli.Exit(fmt.Sprintf("Error: Dependency '%s' not found in %s.", depName, config.ProjectTomlName), 1)
			}

			dependencyPath := dep.Path
			dependencySource := dep.Source // Store source for version display
			// Remove the dependency from the manifest
			delete(proj.Dependencies, depName)

			// Save the updated manifest
			if err := config.WriteProjectToml(".", proj); err != nil {
				return cli.Exit(fmt.Sprintf("Error: Failed to update %s: %v", config.ProjectTomlName, err), 1)
			}
			// fmt.Printf("Successfully removed dependency '%s' from %s.\n", depName, config.ProjectTomlName) // Silenced

			// Delete the dependency file
			fileDeleted := false
			if err := os.Remove(dependencyPath); err != nil {
				if !os.IsNotExist(err) {
					// Keep manifest change, but report error for file deletion
					_, _ = fmt.Fprintf(c.App.ErrWriter, "Warning: Failed to delete dependency file '%s': %v. Manifest updated.\n", dependencyPath, err)
				}
				// fmt.Printf("Warning: Dependency file '%s' not found for deletion, but manifest updated.\n", dependencyPath) // Silenced
			} else {
				// fmt.Printf("Successfully deleted dependency file '%s'.\n", dependencyPath) // Silenced
				fileDeleted = true
				// Attempt to clean up empty parent directories
				currentDir := filepath.Dir(dependencyPath)
				projectRootAbs, errAbs := filepath.Abs(".")
				if errAbs != nil {
					_, _ = fmt.Fprintf(c.App.ErrWriter, "Warning: Could not determine project root absolute path: %v. Skipping directory cleanup.\n", errAbs)
				} else {
					for {
						absCurrentDir, errLoopAbs := filepath.Abs(currentDir)
						if errLoopAbs != nil {
							_, _ = fmt.Fprintf(c.App.ErrWriter, "Warning: Could not get absolute path for '%s': %v. Stopping directory cleanup.\n", currentDir, errLoopAbs)
							break
						}
						if absCurrentDir == projectRootAbs || filepath.Dir(absCurrentDir) == absCurrentDir || currentDir == "." {
							break
						}
						empty, errEmpty := isDirEmpty(currentDir)
						if errEmpty != nil {
							_, _ = fmt.Fprintf(c.App.ErrWriter, "Warning: Could not check if directory '%s' is empty: %v. Stopping directory cleanup.\n", currentDir, errEmpty)
							break
						}
						if !empty {
							break
						}
						// fmt.Printf("Info: Directory '%s' is empty, attempting to remove.\n", currentDir) // Silenced
						if errRemoveDir := os.Remove(currentDir); errRemoveDir != nil {
							_, _ = fmt.Fprintf(c.App.ErrWriter, "Warning: Failed to remove empty directory '%s': %v. Stopping directory cleanup.\n", currentDir, errRemoveDir)
							break
						}
						// fmt.Printf("Successfully removed empty directory '%s'.\n", currentDir) // Silenced
						currentDir = filepath.Dir(currentDir)
					}
				}
			}

			// Update lockfile
			lf, errLock := lockfile.Load(".")
			lockfileUpdated := false
			if errLock != nil {
				_, _ = fmt.Fprintf(c.App.ErrWriter, "Warning: Failed to load %s: %v. Manifest and file processed.\n", lockfile.LockfileName, errLock)
			} else {
				if lf.Package != nil {
					if _, depInLock := lf.Package[depName]; depInLock {
						delete(lf.Package, depName)
						if errSaveLock := lockfile.Save(".", lf); errSaveLock != nil {
							_, _ = fmt.Fprintf(c.App.ErrWriter, "Warning: Failed to update %s: %v. Manifest and file processed.\n", lockfile.LockfileName, errSaveLock)
						} else {
							// fmt.Printf("Successfully removed dependency '%s' from %s.\n", depName, lockfile.LockfileName) // Silenced
							lockfileUpdated = true
						}
					}
					// else {
					// fmt.Printf("Info: Dependency '%s' not found in %s. No changes made to lockfile.\n", depName, lockfile.LockfileName) // Silenced
					// }
				}
				// else {
				// fmt.Printf("Info: No 'package' section found in %s. No changes made to lockfile.\n", lockfile.LockfileName) // Silenced
				// }
			}

			// pnpm-style output
			// For remove, pnpm doesn't show "Packages: -1" but rather "Progress: ... removed 1" or similar.
			// We'll simplify to match the example's structure.
			fmt.Println("Progress: resolved 0, reused 0, downloaded 0, removed 1, done") // Simplified
			fmt.Println()
			_, _ = color.New(color.FgWhite, color.Bold).Println("dependencies:")

			// Try to get version from the original source string in project.toml
			// This is a simplification; a more robust way would be to parse the canonical source string.
			versionStr := "unknown"
			// Use source.ParseSourceURL which is designed for this
			parsedInfo, parseErr := source.ParseSourceURL(dependencySource)
			if parseErr == nil && parsedInfo != nil && parsedInfo.Ref != "" && !strings.HasPrefix(parsedInfo.Ref, "error:") {
				versionStr = parsedInfo.Ref
			}

			_, _ = color.New(color.FgRed).Printf("- %s %s\n", depName, versionStr)
			fmt.Println()
			duration := time.Since(startTime)
			fmt.Printf("Done in %.1fs\n", duration.Seconds())

			// Report on what was actually done, if not fully successful
			// Ensure c.App is not nil before accessing c.App.ErrWriter
			var errWriter io.Writer = os.Stderr // Use io.Writer type
			if c.App != nil && c.App.ErrWriter != nil {
				errWriter = c.App.ErrWriter
			}

			if !fileDeleted {
				_, _ = fmt.Fprintf(errWriter, "Note: Dependency file '%s' was not deleted (either not found or error during deletion).\n", dependencyPath)
			}
			if !lockfileUpdated && errLock == nil { // Only if lockfile was loaded successfully but not updated
				_, _ = fmt.Fprintf(errWriter, "Note: Lockfile '%s' was not updated for '%s' (either not found in lockfile or error during save).\n", lockfile.LockfileName, depName)
			}

			return nil
		},
	}
}
