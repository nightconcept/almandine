// Package add implements the 'add' command for Almandine CLI.
// It downloads external dependencies, saves them to the project,
// and maintains project configuration and lock files.
package add

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/fatih/color"
	"github.com/nightconcept/almandine/internal/core/config"
	"github.com/nightconcept/almandine/internal/core/downloader"
	"github.com/nightconcept/almandine/internal/core/hasher"
	"github.com/nightconcept/almandine/internal/core/lockfile"
	"github.com/nightconcept/almandine/internal/core/project"
	"github.com/nightconcept/almandine/internal/core/source"
	"github.com/urfave/cli/v2"
)

// getFileNameWithoutExtension returns the filename portion without its extension.
func getFileNameWithoutExtension(fileName string) string {
	return strings.TrimSuffix(fileName, filepath.Ext(fileName))
}

// getFileExtension returns just the extension portion of a filename.
func getFileExtension(fileName string) string {
	return filepath.Ext(fileName)
}

// AddCmd provides the CLI command definition for 'add'.
// It downloads a dependency from a source URL and integrates it into the project,
// updating both project.toml and almd-lock.toml accordingly.
func AddCmd() *cli.Command {
	return &cli.Command{
		Name:      "add",
		Usage:     "Downloads a dependency and adds it to the project",
		ArgsUsage: "<source_url>",
		Flags: []cli.Flag{
			&cli.StringFlag{
				Name:    "directory",
				Aliases: []string{"d"},
				Usage:   "Specify the target directory for the dependency",
				Value:   "src/lib/",
			},
			&cli.StringFlag{
				Name:    "name",
				Aliases: []string{"n"},
				Usage:   "Specify the name for the dependency (defaults to filename from URL)",
			},
			&cli.BoolFlag{
				Name:  "verbose",
				Usage: "Enable verbose output",
			},
		},
		Action: func(cCtx *cli.Context) (err error) {
			startTime := time.Now()
			sourceURLInput := ""
			if cCtx.NArg() > 0 {
				sourceURLInput = cCtx.Args().Get(0)
			} else {
				err = cli.Exit("Error: <source_url> argument is required.", 1)
				return
			}

			targetDir := cCtx.String("directory")
			customName := cCtx.String("name")
			verbose := cCtx.Bool("verbose")

			_ = verbose // Keeping verbose flag for future expansion of detailed logging

			var parsedInfo *source.ParsedSourceInfo
			parsedInfo, err = source.ParseSourceURL(sourceURLInput)
			if err != nil {
				err = cli.Exit(fmt.Sprintf("Error parsing source URL '%s': %v", sourceURLInput, err), 1)
				return
			}

			var fileContent []byte
			fileContent, err = downloader.DownloadFile(parsedInfo.RawURL)
			if err != nil {
				err = cli.Exit(fmt.Sprintf("Error downloading file from '%s': %v", parsedInfo.RawURL, err), 1)
				return
			}

			// Determine the final filenames for both the manifest and disk storage
			var dependencyNameInManifest string
			var fileNameOnDisk string

			suggestedBaseName := getFileNameWithoutExtension(parsedInfo.SuggestedFilename)
			suggestedExtension := getFileExtension(parsedInfo.SuggestedFilename)

			if customName != "" {
				dependencyNameInManifest = customName
				fileNameOnDisk = customName + suggestedExtension
			} else {
				if suggestedBaseName == "" || suggestedBaseName == "." || suggestedBaseName == "/" {
					err = cli.Exit(fmt.Sprintf("Error: Could not infer a valid base filename from URL's suggested filename: '%s'. Use -n to specify a name.", parsedInfo.SuggestedFilename), 1)
					return
				}
				dependencyNameInManifest = suggestedBaseName
				fileNameOnDisk = parsedInfo.SuggestedFilename
			}

			if fileNameOnDisk == "" || fileNameOnDisk == "." || fileNameOnDisk == "/" {
				err = cli.Exit("Error: Could not determine a valid final filename for saving. Inferred name was empty or invalid.", 1)
				return
			}

			projectRoot := "."
			fullPath := filepath.Join(projectRoot, targetDir, fileNameOnDisk)
			relativeDestPath := filepath.ToSlash(filepath.Join(targetDir, fileNameOnDisk))

			// Create directories before writing file to ensure proper cleanup on failure
			dirToCreate := filepath.Dir(fullPath)
			if mkdirErr := os.MkdirAll(dirToCreate, 0755); mkdirErr != nil {
				err = cli.Exit(fmt.Sprintf("Error creating directory '%s': %v", dirToCreate, mkdirErr), 1)
				return
			}

			// Track if file was written to ensure proper cleanup on errors
			fileWritten := false
			if writeErr := os.WriteFile(fullPath, fileContent, 0644); writeErr != nil {
				err = cli.Exit(fmt.Sprintf("Error writing file '%s': %v", fullPath, writeErr), 1)
				return
			}
			fileWritten = true

			// Cleanup downloaded file if any subsequent operations fail
			defer func() {
				if err != nil && fileWritten {
					cleanupErr := os.Remove(fullPath)
					if cleanupErr != nil {
						var errWriter io.Writer = os.Stderr
						if cCtx.App != nil && cCtx.App.ErrWriter != nil {
							errWriter = cCtx.App.ErrWriter
						}
						_, _ = fmt.Fprintf(errWriter, "Warning: Failed to clean up downloaded file '%s' during error handling: %v\n", fullPath, cleanupErr)
					}
				}
			}()

			// Calculate content hash for integrity verification
			var fileHashSHA256 string
			var hashErr error
			fileHashSHA256, hashErr = hasher.CalculateSHA256(fileContent)
			if hashErr != nil {
				err = cli.Exit(fmt.Sprintf("Error calculating SHA256 hash: %v. File '%s' was saved but is now being cleaned up.", hashErr, fullPath), 1)
				return
			}

			var proj *project.Project
			var loadTomlErr error
			proj, loadTomlErr = config.LoadProjectToml(projectRoot)
			if loadTomlErr != nil {
				if os.IsNotExist(loadTomlErr) {
					expectedProjectTomlPath := filepath.Join(projectRoot, config.ProjectTomlName)
					detailedError := fmt.Errorf("project.toml not found at '%s' (no such file or directory): %w", expectedProjectTomlPath, loadTomlErr)
					err = cli.Exit(fmt.Sprintf("Error: %s. File '%s' was saved but is now being cleaned up.", detailedError, fullPath), 1)
					return
				} else {
					err = cli.Exit(fmt.Sprintf("Error loading %s: %v. File '%s' was saved but is now being cleaned up.", config.ProjectTomlName, loadTomlErr, fullPath), 1)
					return
				}
			}

			// Ensure dependencies map is initialized
			if proj.Dependencies == nil {
				proj.Dependencies = make(map[string]project.Dependency)
			}

			proj.Dependencies[dependencyNameInManifest] = project.Dependency{
				Source: parsedInfo.CanonicalURL,
				Path:   relativeDestPath,
			}

			if writeTomlErr := config.WriteProjectToml(projectRoot, proj); writeTomlErr != nil {
				err = cli.Exit(fmt.Sprintf("Error writing %s: %v. File '%s' was saved but is now being cleaned up. %s may be in an inconsistent state.", config.ProjectTomlName, writeTomlErr, fullPath, config.ProjectTomlName), 1)
				return
			}

			var lf *lockfile.Lockfile
			var loadLockErr error
			lf, loadLockErr = lockfile.Load(projectRoot)
			if loadLockErr != nil {
				err = cli.Exit(fmt.Sprintf("Error loading/initializing %s: %v. File '%s' saved and %s updated, but lockfile operation failed. %s and %s may be inconsistent. Downloaded file '%s' is being cleaned up.", lockfile.LockfileName, loadLockErr, fullPath, config.ProjectTomlName, config.ProjectTomlName, lockfile.LockfileName, fullPath), 1)
				return
			}

			// Determine integrity hash based on commit SHA or content hash
			var integrityHash string
			isLikelyCommitSHA := func(ref string) bool {
				if len(ref) != 40 {
					return false
				}
				for _, r := range ref {
					if (r < '0' || r > '9') && (r < 'a' || r > 'f') && (r < 'A' || r > 'F') {
						return false
					}
				}
				return true
			}

			if parsedInfo.Provider == "github" && parsedInfo.Owner != "" && parsedInfo.Repo != "" && parsedInfo.PathInRepo != "" && parsedInfo.Ref != "" && !strings.HasPrefix(parsedInfo.Ref, "error:") {
				if isLikelyCommitSHA(parsedInfo.Ref) {
					integrityHash = fmt.Sprintf("commit:%s", parsedInfo.Ref)
				} else {
					var commitSHA string
					var getCommitErr error
					commitSHA, getCommitErr = source.GetLatestCommitSHAForFile(parsedInfo.Owner, parsedInfo.Repo, parsedInfo.PathInRepo, parsedInfo.Ref)
					if getCommitErr != nil {
						integrityHash = fileHashSHA256
					} else {
						integrityHash = fmt.Sprintf("commit:%s", commitSHA)
					}
				}
			} else {
				integrityHash = fileHashSHA256
			}

			lf.AddOrUpdatePackage(dependencyNameInManifest, parsedInfo.RawURL, relativeDestPath, integrityHash)

			if saveLockErr := lockfile.Save(projectRoot, lf); saveLockErr != nil {
				err = cli.Exit(fmt.Sprintf("Error saving %s: %v. File '%s' saved and %s updated, but saving %s failed. %s and %s may be inconsistent. Downloaded file '%s' is being cleaned up.", lockfile.LockfileName, saveLockErr, fullPath, config.ProjectTomlName, lockfile.LockfileName, config.ProjectTomlName, lockfile.LockfileName, fullPath), 1)
				return
			}

			_, _ = color.New(color.FgWhite).Println("Packages: +1")
			_, _ = color.New(color.FgGreen).Println("++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++")
			fmt.Println("Progress: resolved 1, downloaded 1, added 1, done")
			fmt.Println()
			_, _ = color.New(color.FgWhite, color.Bold).Println("dependencies:")
			dependencyVersionStr := parsedInfo.Ref
			if dependencyVersionStr == "" || strings.HasPrefix(dependencyVersionStr, "error:") {
				parts := strings.Split(parsedInfo.CanonicalURL, "@")
				if len(parts) > 1 {
					dependencyVersionStr = parts[len(parts)-1]
				} else {
					dependencyVersionStr = "latest"
				}
			}
			_, _ = color.New(color.FgGreen).Printf("+ %s %s\n", dependencyNameInManifest, dependencyVersionStr)
			fmt.Println()
			duration := time.Since(startTime)
			fmt.Printf("Done in %.1fs\n", duration.Seconds())

			return nil
		},
	}
}
