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

// RemoveCmd handles the 'remove' subcommand
func RemoveCmd() *cli.Command {
	return &cli.Command{
		Name:      "remove",
		Usage:     "Remove a dependency from the project",
		ArgsUsage: "DEPENDENCY",
		Action: func(c *cli.Context) error {
			startTime := time.Now()
			if !c.Args().Present() {
				return cli.Exit("Error: Dependency name argument is required.", 1)
			}

			depName := c.Args().First()

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
			dependencySource := dep.Source
			delete(proj.Dependencies, depName)

			if err := config.WriteProjectToml(".", proj); err != nil {
				return cli.Exit(fmt.Sprintf("Error: Failed to update %s: %v", config.ProjectTomlName, err), 1)
			}

			fileDeleted := false
			if err := os.Remove(dependencyPath); err != nil {
				if !os.IsNotExist(err) {
					_, _ = fmt.Fprintf(c.App.ErrWriter, "Warning: Failed to delete dependency file '%s': %v. Manifest updated.\n", dependencyPath, err)
				}
			} else {
				fileDeleted = true
				currentDir := filepath.Dir(dependencyPath)
				projectRootAbs, errAbs := filepath.Abs(".")
				if errAbs != nil {
					_, _ = fmt.Fprintf(c.App.ErrWriter, "Warning: Could not determine project root absolute path: %v. Skipping directory cleanup.\n", errAbs)
				} else {
					// Recursively clean up empty parent directories up to project root
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
						if errRemoveDir := os.Remove(currentDir); errRemoveDir != nil {
							_, _ = fmt.Fprintf(c.App.ErrWriter, "Warning: Failed to remove empty directory '%s': %v. Stopping directory cleanup.\n", currentDir, errRemoveDir)
							break
						}
						currentDir = filepath.Dir(currentDir)
					}
				}
			}

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
							lockfileUpdated = true
						}
					}
				}
			}

			fmt.Println("Progress: resolved 0, reused 0, downloaded 0, removed 1, done")
			fmt.Println()
			_, _ = color.New(color.FgWhite, color.Bold).Println("dependencies:")

			// Use "unknown" for version when ref is missing or invalid to maintain consistent output format
			versionStr := "unknown"
			parsedInfo, parseErr := source.ParseSourceURL(dependencySource)
			if parseErr == nil && parsedInfo != nil && parsedInfo.Ref != "" && !strings.HasPrefix(parsedInfo.Ref, "error:") {
				versionStr = parsedInfo.Ref
			}

			_, _ = color.New(color.FgRed).Printf("- %s %s\n", depName, versionStr)
			fmt.Println()
			duration := time.Since(startTime)
			fmt.Printf("Done in %.1fs\n", duration.Seconds())

			// Fallback to os.Stderr if App.ErrWriter is not configured
			var errWriter io.Writer = os.Stderr
			if c.App != nil && c.App.ErrWriter != nil {
				errWriter = c.App.ErrWriter
			}

			if !fileDeleted {
				_, _ = fmt.Fprintf(errWriter, "Note: Dependency file '%s' was not deleted (either not found or error during deletion).\n", dependencyPath)
			}
			if !lockfileUpdated && errLock == nil {
				_, _ = fmt.Fprintf(errWriter, "Note: Lockfile '%s' was not updated for '%s' (either not found in lockfile or error during save).\n", lockfile.LockfileName, depName)
			}

			return nil
		},
	}
}
