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

// Helper function to parse CLI arguments for the add command.
func parseAddArgs(cCtx *cli.Context) (sourceURLInput, targetDir, customName string, verbose bool, err error) {
	if cCtx.NArg() > 0 {
		sourceURLInput = cCtx.Args().Get(0)
	} else {
		return "", "", "", false, fmt.Errorf("<source_url> argument is required")
	}
	targetDir = cCtx.String("directory")
	customName = cCtx.String("name")
	verbose = cCtx.Bool("verbose")
	return
}

// Helper function to process the source URL.
func processSourceURL(sourceURLInput string) (*source.ParsedSourceInfo, error) {
	parsedInfo, err := source.ParseSourceURL(sourceURLInput)
	if err != nil {
		return nil, fmt.Errorf("parsing source URL '%s': %w", sourceURLInput, err)
	}
	return parsedInfo, nil
}

// Helper function to download the dependency file.
func downloadDependency(rawURL string) ([]byte, error) {
	fileContent, err := downloader.DownloadFile(rawURL)
	if err != nil {
		return nil, fmt.Errorf("downloading file from '%s': %w", rawURL, err)
	}
	return fileContent, nil
}

// Helper function to determine manifest and disk filenames.
func determineFileNames(parsedInfo *source.ParsedSourceInfo, customName string) (dependencyNameInManifest, fileNameOnDisk string, err error) {
	suggestedBaseName := strings.TrimSuffix(parsedInfo.SuggestedFilename, filepath.Ext(parsedInfo.SuggestedFilename))
	suggestedExtension := filepath.Ext(parsedInfo.SuggestedFilename)

	if customName != "" {
		dependencyNameInManifest = customName
		fileNameOnDisk = customName + suggestedExtension
	} else {
		if suggestedBaseName == "" || suggestedBaseName == "." || suggestedBaseName == "/" {
			return "", "", fmt.Errorf("could not infer a valid base filename from URL's suggested filename: '%s'. Use -n to specify a name", parsedInfo.SuggestedFilename)
		}
		dependencyNameInManifest = suggestedBaseName
		fileNameOnDisk = parsedInfo.SuggestedFilename
	}

	if fileNameOnDisk == "" || fileNameOnDisk == "." || fileNameOnDisk == "/" {
		return "", "", fmt.Errorf("could not determine a valid final filename for saving. Inferred name was empty or invalid")
	}
	return dependencyNameInManifest, fileNameOnDisk, nil
}

// Helper function to save the dependency file to disk.
func saveDependencyFile(projectRoot, targetDir, fileNameOnDisk string, fileContent []byte) (fullPath, relativeDestPath string, err error) {
	fullPath = filepath.Join(projectRoot, targetDir, fileNameOnDisk)
	relativeDestPath = filepath.ToSlash(filepath.Join(targetDir, fileNameOnDisk))

	dirToCreate := filepath.Dir(fullPath)
	if mkdirErr := os.MkdirAll(dirToCreate, 0755); mkdirErr != nil {
		return "", "", fmt.Errorf("creating directory '%s': %w", dirToCreate, mkdirErr)
	}

	if writeErr := os.WriteFile(fullPath, fileContent, 0644); writeErr != nil {
		return fullPath, "", fmt.Errorf("writing file '%s': %w", fullPath, writeErr) // Return fullPath for potential cleanup
	}
	return fullPath, relativeDestPath, nil
}

// Helper function to calculate the integrity hash for the lockfile.
func calculateIntegrityHash(parsedInfo *source.ParsedSourceInfo, fileContent []byte) (string, error) {
	fileHashSHA256, hashErr := hasher.CalculateSHA256(fileContent)
	if hashErr != nil {
		return "", fmt.Errorf("calculating SHA256 hash: %w", hashErr)
	}

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
			return fmt.Sprintf("commit:%s", parsedInfo.Ref), nil
		}
		commitSHA, getCommitErr := source.GetLatestCommitSHAForFile(parsedInfo.Owner, parsedInfo.Repo, parsedInfo.PathInRepo, parsedInfo.Ref)
		if getCommitErr != nil {
			// Fallback to SHA256 if commit SHA cannot be fetched
			return fileHashSHA256, nil
		}
		return fmt.Sprintf("commit:%s", commitSHA), nil
	}
	return fileHashSHA256, nil
}

// Helper function to update the project.toml manifest.
func updateProjectManifest(projectRoot, dependencyNameInManifest, canonicalURL, relativeDestPath string) error {
	proj, loadTomlErr := config.LoadProjectToml(projectRoot)
	if loadTomlErr != nil {
		if os.IsNotExist(loadTomlErr) {
			expectedProjectTomlPath := filepath.Join(projectRoot, config.ProjectTomlName)
			return fmt.Errorf("project.toml not found at '%s' (no such file or directory): %w", expectedProjectTomlPath, loadTomlErr)
		}
		return fmt.Errorf("loading %s: %w", config.ProjectTomlName, loadTomlErr)
	}

	if proj.Dependencies == nil {
		proj.Dependencies = make(map[string]project.Dependency)
	}
	proj.Dependencies[dependencyNameInManifest] = project.Dependency{
		Source: canonicalURL,
		Path:   relativeDestPath,
	}

	if writeTomlErr := config.WriteProjectToml(projectRoot, proj); writeTomlErr != nil {
		return fmt.Errorf("writing %s: %w", config.ProjectTomlName, writeTomlErr)
	}
	return nil
}

// Helper function to update the almd-lock.toml lockfile.
func updateLockfile(projectRoot, dependencyNameInManifest, rawURL, relativeDestPath, integrityHash string) error {
	lf, loadLockErr := lockfile.Load(projectRoot)
	if loadLockErr != nil {
		// If lockfile doesn't exist, Load creates a new one, so this error is likely a real issue.
		return fmt.Errorf("loading/initializing %s: %w", lockfile.LockfileName, loadLockErr)
	}

	lf.AddOrUpdatePackage(dependencyNameInManifest, rawURL, relativeDestPath, integrityHash)

	if saveLockErr := lockfile.Save(projectRoot, lf); saveLockErr != nil {
		return fmt.Errorf("saving %s: %w", lockfile.LockfileName, saveLockErr)
	}
	return nil
}

// AddCmd provides the CLI command definition for 'add'.
func AddCmd() *cli.Command {
	return &cli.Command{
		Name:      "add",
		Usage:     "Downloads a dependency and adds it to the project",
		ArgsUsage: "<source_url>",
		Flags: []cli.Flag{
			&cli.StringFlag{Name: "directory", Aliases: []string{"d"}, Usage: "Specify the target directory for the dependency", Value: "src/lib/"},
			&cli.StringFlag{Name: "name", Aliases: []string{"n"}, Usage: "Specify the name for the dependency (defaults to filename from URL)"},
			&cli.BoolFlag{Name: "verbose", Usage: "Enable verbose output"},
		},
		Action: func(cCtx *cli.Context) (err error) {
			startTime := time.Now()
			projectRoot := "." // Assuming current directory is project root

			sourceURLInput, targetDir, customName, verbose, err := parseAddArgs(cCtx)
			if err != nil {
				return cli.Exit(fmt.Sprintf("Error: %v", err), 1)
			}
			_ = verbose // Placeholder for future verbose logging

			parsedInfo, err := processSourceURL(sourceURLInput)
			if err != nil {
				return cli.Exit(fmt.Sprintf("Error: %v", err), 1)
			}

			fileContent, err := downloadDependency(parsedInfo.RawURL)
			if err != nil {
				return cli.Exit(fmt.Sprintf("Error: %v", err), 1)
			}

			dependencyNameInManifest, fileNameOnDisk, err := determineFileNames(parsedInfo, customName)
			if err != nil {
				return cli.Exit(fmt.Sprintf("Error: %v", err), 1)
			}

			fullPath, relativeDestPath, err := saveDependencyFile(projectRoot, targetDir, fileNameOnDisk, fileContent)
			fileWritten := err == nil || (err != nil && fullPath != "") // file might be partially written on error

			// Defer cleanup logic
			defer func() {
				if err != nil && fileWritten { // If an error occurred AND a file was (potentially partially) written
					cleanupErr := os.Remove(fullPath)
					if cleanupErr != nil {
						// Use cCtx.App.ErrWriter if available for consistent error output
						var errWriter io.Writer = os.Stderr
						if cCtx.App != nil && cCtx.App.ErrWriter != nil {
							errWriter = cCtx.App.ErrWriter
						}
						_, _ = fmt.Fprintf(errWriter, "Warning: Failed to clean up downloaded file '%s' during error handling: %v\n", fullPath, cleanupErr)
					}
				}
			}()

			if err != nil { // This error is from saveDependencyFile
				return cli.Exit(fmt.Sprintf("Error: %v", err), 1)
			}
			// At this point, file is successfully written.
			// Subsequent errors will trigger the deferred cleanup.

			integrityHash, err := calculateIntegrityHash(parsedInfo, fileContent)
			if err != nil {
				// Error from calculateIntegrityHash, deferred cleanup will run.
				return cli.Exit(fmt.Sprintf("Error: %v. File '%s' was saved but is now being cleaned up.", err, fullPath), 1)
			}

			err = updateProjectManifest(projectRoot, dependencyNameInManifest, parsedInfo.CanonicalURL, relativeDestPath)
			if err != nil {
				// Error from updateProjectManifest, deferred cleanup will run.
				return cli.Exit(fmt.Sprintf("Error: %v. File '%s' was saved but is now being cleaned up. %s may be in an inconsistent state.", err, fullPath, config.ProjectTomlName), 1)
			}

			err = updateLockfile(projectRoot, dependencyNameInManifest, parsedInfo.RawURL, relativeDestPath, integrityHash)
			if err != nil {
				// Error from updateLockfile, deferred cleanup will run.
				return cli.Exit(fmt.Sprintf("Error: %v. File '%s' saved and %s updated, but lockfile operation failed. %s and %s may be inconsistent. Downloaded file '%s' is being cleaned up.", err, fullPath, config.ProjectTomlName, config.ProjectTomlName, lockfile.LockfileName, fullPath), 1)
			}

			// Success: print output
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
					dependencyVersionStr = "latest" // Or some other default
				}
			}
			_, _ = color.New(color.FgGreen).Printf("+ %s %s\n", dependencyNameInManifest, dependencyVersionStr)
			fmt.Println()
			duration := time.Since(startTime)
			fmt.Printf("Done in %.1fs\n", duration.Seconds())

			return nil // Explicitly return nil on success
		},
	}
}
