// Package add implements the 'add' command for Almandine CLI.
// It downloads external dependencies, saves them to the project,
// and maintains project configuration and lock files.
package add

import (
	"encoding/hex"
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

// isGitHubSourceWithSufficientInfo checks if the parsed source information
// points to a GitHub source with all necessary details for advanced integrity checks.
func isGitHubSourceWithSufficientInfo(p *source.ParsedSourceInfo) bool {
	return p.Provider == "github" &&
		p.Owner != "" &&
		p.Repo != "" &&
		p.PathInRepo != "" &&
		p.Ref != "" &&
		!strings.HasPrefix(p.Ref, "error:")
}

// determineGitHubIntegrity attempts to determine a commit-based integrity string for GitHub sources.
// If the ref is already a commit SHA, it's used. Otherwise, it attempts to fetch the latest commit SHA.
// If fetching fails or is not applicable, it returns the fallbackHashSHA256.
func determineGitHubIntegrity(parsedInfo *source.ParsedSourceInfo, fallbackHashSHA256 string) string {
	// isLikelyCommitSHA checks if the ref string looks like a 40-char hex string (e.g., a full commit SHA).
	isLikelyCommitSHA := func(ref string) bool {
		if len(ref) != 40 {
			return false
		}
		_, err := hex.DecodeString(ref)
		return err == nil
	}

	if isLikelyCommitSHA(parsedInfo.Ref) {
		return fmt.Sprintf("commit:%s", parsedInfo.Ref)
	}

	// Attempt to get the specific commit SHA for the file at the given ref.
	commitSHA, err := source.GetLatestCommitSHAForFile(parsedInfo.Owner, parsedInfo.Repo, parsedInfo.PathInRepo, parsedInfo.Ref)
	if err != nil {
		// If fetching the specific commit SHA fails, fallback to the provided SHA256 hash.
		// Consider logging err here if verbose mode is enabled or for debugging.
		return fallbackHashSHA256
	}
	return fmt.Sprintf("commit:%s", commitSHA)
}

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

func processSourceURL(sourceURLInput string) (*source.ParsedSourceInfo, error) {
	parsedInfo, err := source.ParseSourceURL(sourceURLInput)
	if err != nil {
		return nil, fmt.Errorf("parsing source URL '%s': %w", sourceURLInput, err)
	}
	return parsedInfo, nil
}

func downloadDependency(rawURL string) ([]byte, error) {
	fileContent, err := downloader.DownloadFile(rawURL)
	if err != nil {
		return nil, fmt.Errorf("downloading file from '%s': %w", rawURL, err)
	}
	return fileContent, nil
}

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

func calculateIntegrityHash(parsedInfo *source.ParsedSourceInfo, fileContent []byte) (string, error) {
	fileHashSHA256, hashErr := hasher.CalculateSHA256(fileContent)
	if hashErr != nil {
		return "", fmt.Errorf("calculating SHA256 hash: %w", hashErr)
	}

	if isGitHubSourceWithSufficientInfo(parsedInfo) {
		return determineGitHubIntegrity(parsedInfo, fileHashSHA256), nil
	}

	return fileHashSHA256, nil
}

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

// determineDisplayVersion determines the version string to display for a dependency.
// It prioritizes the Ref field, then tries to parse from CanonicalURL, and defaults to "latest".
func determineDisplayVersion(parsedInfo *source.ParsedSourceInfo) string {
	versionStr := parsedInfo.Ref
	if versionStr == "" || strings.HasPrefix(versionStr, "error:") {
		parts := strings.Split(parsedInfo.CanonicalURL, "@")
		if len(parts) > 1 {
			return parts[len(parts)-1]
		}
		return "latest" // Default if no version info found
	}
	return versionStr
}

// performCleanupOnPotentialError is called by a defer in AddCmd.Action.
// It checks if an error occurred during the AddCmd action and if a file was (potentially) written,
// then attempts to clean up the file, warning if the cleanup fails.
func performCleanupOnPotentialError(actionErr error, fileWasWritten bool, filePathToDelete string, cCtx *cli.Context) {
	if actionErr != nil && fileWasWritten {
		cleanupErr := os.Remove(filePathToDelete)
		if cleanupErr != nil {
			var errWriter io.Writer = os.Stderr // Default to os.Stderr
			if cCtx.App != nil && cCtx.App.ErrWriter != nil {
				errWriter = cCtx.App.ErrWriter
			}
			_, _ = fmt.Fprintf(errWriter, "Warning: Failed to clean up downloaded file '%s' during error handling: %v\n", filePathToDelete, cleanupErr)
		}
	}
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
		Action: func(cCtx *cli.Context) (err error) { // Named return 'err' for defer to access
			startTime := time.Now()
			projectRoot := "." // Assuming current directory is project root

			sourceURLInput, targetDir, customName, verbose, parseErr := parseAddArgs(cCtx)
			if parseErr != nil {
				err = cli.Exit(fmt.Sprintf("Error parsing 'add' arguments: %v", parseErr), 1)
				return
			}
			_ = verbose // Placeholder for future verbose logging

			parsedInfo, processURLErr := processSourceURL(sourceURLInput)
			if processURLErr != nil {
				err = cli.Exit(fmt.Sprintf("Error processing source URL '%s': %v", sourceURLInput, processURLErr), 1)
				return
			}

			fileContent, downloadErr := downloadDependency(parsedInfo.RawURL)
			if downloadErr != nil {
				err = cli.Exit(fmt.Sprintf("Error downloading from '%s': %v", parsedInfo.RawURL, downloadErr), 1)
				return
			}

			dependencyNameInManifest, fileNameOnDisk, determineNamesErr := determineFileNames(parsedInfo, customName)
			if determineNamesErr != nil {
				err = cli.Exit(fmt.Sprintf("Error determining file names: %v", determineNamesErr), 1)
				return
			}

			fullPath, relativeDestPath, saveFileErr := saveDependencyFile(projectRoot, targetDir, fileNameOnDisk, fileContent)
			fileWritten := saveFileErr == nil || (saveFileErr != nil && fullPath != "")

			defer func() {
				performCleanupOnPotentialError(err, fileWritten, fullPath, cCtx)
			}()

			if saveFileErr != nil {
				err = cli.Exit(fmt.Sprintf("Error saving dependency file to '%s': %v. Attempting to clean up.", fullPath, saveFileErr), 1)
				return
			}

			integrityHash, integrityHashErr := calculateIntegrityHash(parsedInfo, fileContent)
			if integrityHashErr != nil {
				err = cli.Exit(fmt.Sprintf("Error calculating integrity hash: %v. File '%s' was saved but is now being cleaned up.", integrityHashErr, fullPath), 1)
				return
			}

			manifestErr := updateProjectManifest(projectRoot, dependencyNameInManifest, parsedInfo.CanonicalURL, relativeDestPath)
			if manifestErr != nil {
				err = cli.Exit(fmt.Sprintf("Error updating project manifest: %v. File '%s' was saved but is now being cleaned up. %s may be in an inconsistent state.", manifestErr, fullPath, config.ProjectTomlName), 1)
				return
			}

			lockfileErr := updateLockfile(projectRoot, dependencyNameInManifest, parsedInfo.RawURL, relativeDestPath, integrityHash)
			if lockfileErr != nil {
				err = cli.Exit(fmt.Sprintf("Error updating lockfile: %v. File '%s' saved and %s updated, but lockfile operation failed. %s and %s may be inconsistent. Downloaded file '%s' is being cleaned up.", lockfileErr, fullPath, config.ProjectTomlName, config.ProjectTomlName, lockfile.LockfileName, fullPath), 1)
				return
			}

			// Success: print output
			_, _ = color.New(color.FgWhite).Println("Packages: +1")
			_, _ = color.New(color.FgGreen).Println("++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++")
			fmt.Println("Progress: resolved 1, downloaded 1, added 1, done")
			fmt.Println()
			_, _ = color.New(color.FgWhite, color.Bold).Println("dependencies:")
			dependencyVersionStr := determineDisplayVersion(parsedInfo)
			_, _ = color.New(color.FgGreen).Printf("+ %s %s\n", dependencyNameInManifest, dependencyVersionStr)
			fmt.Println()
			duration := time.Since(startTime)
			fmt.Printf("Done in %.1fs\n", duration.Seconds())

			return nil // Explicitly return nil on success
		},
	}
}
