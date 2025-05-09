// Title: Almandine CLI Add Command
// Purpose: Implements the 'add' command for the Almandine CLI, which downloads
// a specified dependency, saves it to the project, and updates project
// configuration and lock files.
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

// Helper function to get filename without extension
func getFileNameWithoutExtension(fileName string) string {
	return strings.TrimSuffix(fileName, filepath.Ext(fileName))
}

// Helper function to get file extension
func getFileExtension(fileName string) string {
	return filepath.Ext(fileName)
}

// AddCommand defines the structure for the "add" command.
var AddCommand = &cli.Command{
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
	Action: func(cCtx *cli.Context) (err error) { // MODIFIED: Named return error
		startTime := time.Now()
		sourceURLInput := ""
		if cCtx.NArg() > 0 {
			sourceURLInput = cCtx.Args().Get(0) // .First() is equivalent but .Get(0) is more explicit
		} else {
			err = cli.Exit("Error: <source_url> argument is required.", 1) // MODIFIED
			return
		}

		targetDir := cCtx.String("directory")
		customName := cCtx.String("name")
		verbose := cCtx.Bool("verbose")

		// Silence default verbose output, will be replaced by pnpm style
		_ = verbose // Keep verbose for potential future use or more detailed debugging

		// Task 2.2: Parse the source URL
		var parsedInfo *source.ParsedSourceInfo
		parsedInfo, err = source.ParseSourceURL(sourceURLInput) // Assign to named return 'err'
		if err != nil {
			err = cli.Exit(fmt.Sprintf("Error parsing source URL '%s': %v", sourceURLInput, err), 1) // MODIFIED
			return
		}

		if verbose {
			fmt.Printf("Parsed Source Info:\n")
			fmt.Printf("  Raw Download URL: %s\n", parsedInfo.RawURL)
			fmt.Printf("  Canonical URL for Manifest: %s\n", parsedInfo.CanonicalURL)
			fmt.Printf("  Extracted Ref (commit/branch/tag): %s\n", parsedInfo.Ref)
			fmt.Printf("  Suggested Filename from URL: %s\n", parsedInfo.SuggestedFilename)
		}

		// Task 2.3: Download the file using the RawURL
		if verbose {
			fmt.Printf("Downloading from %s...\n", parsedInfo.RawURL)
		}
		var fileContent []byte
		fileContent, err = downloader.DownloadFile(parsedInfo.RawURL) // Assign to named return 'err'
		if err != nil {
			err = cli.Exit(fmt.Sprintf("Error downloading file from '%s': %v", parsedInfo.RawURL, err), 1) // MODIFIED
			return
		}
		if verbose {
			fmt.Printf("Downloaded %d bytes successfully.\n", len(fileContent))
		}

		// Task 2.4: Determine target path and save file
		var dependencyNameInManifest string
		var fileNameOnDisk string

		suggestedBaseName := getFileNameWithoutExtension(parsedInfo.SuggestedFilename)
		suggestedExtension := getFileExtension(parsedInfo.SuggestedFilename)

		if customName != "" {
			dependencyNameInManifest = customName
			fileNameOnDisk = customName + suggestedExtension // Ensure extension is preserved
		} else {
			if suggestedBaseName == "" || suggestedBaseName == "." || suggestedBaseName == "/" {
				err = cli.Exit(fmt.Sprintf("Error: Could not infer a valid base filename from URL's suggested filename: '%s'. Use -n to specify a name.", parsedInfo.SuggestedFilename), 1) // MODIFIED
				return
			}
			dependencyNameInManifest = suggestedBaseName
			fileNameOnDisk = parsedInfo.SuggestedFilename
		}

		if fileNameOnDisk == "" || fileNameOnDisk == "." || fileNameOnDisk == "/" {
			err = cli.Exit("Error: Could not determine a valid final filename for saving. Inferred name was empty or invalid.", 1) // MODIFIED
			return
		}

		if verbose {
			fmt.Printf("Effective filename for saving: %s\n", fileNameOnDisk)
			fmt.Printf("Dependency name in manifest/lockfile: %s\n", dependencyNameInManifest)
		}

		// Construct the full path relative to the current directory (project root)
		projectRoot := "."
		fullPath := filepath.Join(projectRoot, targetDir, fileNameOnDisk)
		relativeDestPath := filepath.ToSlash(filepath.Join(targetDir, fileNameOnDisk))

		if verbose {
			fmt.Printf("Resolved full path for saving: %s\n", fullPath)
			fmt.Printf("Relative destination path for manifest: %s\n", relativeDestPath)
		}

		// Create the target directory if it doesn't exist
		dirToCreate := filepath.Dir(fullPath)
		if verbose {
			fmt.Printf("Ensuring directory exists: %s\n", dirToCreate)
		}
		// Use a temporary variable for MkdirAll's error to not shadow the named return 'err'
		if mkdirErr := os.MkdirAll(dirToCreate, 0755); mkdirErr != nil {
			err = cli.Exit(fmt.Sprintf("Error creating directory '%s': %v", dirToCreate, mkdirErr), 1) // MODIFIED
			return
		}

		// Save the downloaded content to the file
		// This is a critical point: if this succeeds but subsequent steps fail, we should try to clean up this file.
		if verbose {
			fmt.Printf("Saving file to %s...\n", fullPath)
		}
		// Use a temporary variable for WriteFile's error
		if writeErr := os.WriteFile(fullPath, fileContent, 0644); writeErr != nil {
			// No file to clean up yet, as it wasn't written.
			err = cli.Exit(fmt.Sprintf("Error writing file '%s': %v", fullPath, writeErr), 1) // MODIFIED
			return
		}
		// File has been written. From this point on, if an error occurs, we must attempt to clean it up.
		fileWritten := true
		defer func() {
			// 'err' here refers to the named return parameter of the Action func.
			if err != nil && fileWritten { // If an error occurred (i.e., Action is returning an error) and file was written
				if verbose {
					fmt.Printf("Attempting to clean up downloaded file '%s' due to error: %v\n", fullPath, err)
				}
				cleanupErr := os.Remove(fullPath)
				if cleanupErr != nil {
					var errWriter io.Writer = os.Stderr
					if cCtx.App != nil && cCtx.App.ErrWriter != nil {
						errWriter = cCtx.App.ErrWriter
					}
					_, _ = fmt.Fprintf(errWriter, "Warning: Failed to clean up downloaded file '%s' during error handling: %v\n", fullPath, cleanupErr)
				} else {
					if verbose {
						fmt.Printf("Successfully cleaned up downloaded file '%s'.\n", fullPath)
					}
				}
			}
		}()

		// Task 2.5: Calculate hash of the downloaded content
		var fileHashSHA256 string
		var hashErr error
		fileHashSHA256, hashErr = hasher.CalculateSHA256(fileContent)
		if hashErr != nil {
			// Assign to named return 'err'
			err = cli.Exit(fmt.Sprintf("Error calculating SHA256 hash: %v. File '%s' was saved but is now being cleaned up.", hashErr, fullPath), 1) // MODIFIED
			return
		}
		if verbose {
			fmt.Printf("SHA256 hash of downloaded file: %s\n", fileHashSHA256)
		}

		// Task 2.7: Update project.toml
		if verbose {
			fmt.Println("Updating project.toml...")
		}
		// projectTomlPath variable is no longer needed as LoadProjectToml and WriteProjectToml
		// now correctly use projectRoot to construct the path internally.
		var proj *project.Project // MODIFIED: Use pointer type
		var loadTomlErr error
		// Pass projectRoot to LoadProjectToml, not the full path to the file
		proj, loadTomlErr = config.LoadProjectToml(projectRoot)
		if loadTomlErr != nil {
			if os.IsNotExist(loadTomlErr) {
				// Construct the expected full path for a more accurate error message if needed,
				// though LoadProjectToml itself will return the error from os.ReadFile(filepath.Join(projectRoot, config.ProjectTomlName))
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

		// For project.toml, use the canonical source identifier
		proj.Dependencies[dependencyNameInManifest] = project.Dependency{
			Source: parsedInfo.CanonicalURL,
			Path:   relativeDestPath,
		}

		// Use a temporary variable for WriteProjectToml's error
		// Pass projectRoot to WriteProjectToml, not the full path to the file
		if writeTomlErr := config.WriteProjectToml(projectRoot, proj); writeTomlErr != nil { // proj is already a pointer
			err = cli.Exit(fmt.Sprintf("Error writing %s: %v. File '%s' was saved but is now being cleaned up. %s may be in an inconsistent state.", config.ProjectTomlName, writeTomlErr, fullPath, config.ProjectTomlName), 1)
			return
		}

		if verbose {
			fmt.Printf("Successfully updated %s for dependency '%s'.\n", config.ProjectTomlName, dependencyNameInManifest)
		}

		// Task 2.8: Implement Lockfile Update
		if verbose {
			fmt.Println("Updating almd-lock.toml...")
		}

		var lf *lockfile.Lockfile // MODIFIED: Use pointer type and correct package
		var loadLockErr error
		lf, loadLockErr = lockfile.Load(projectRoot) // Load or initialize if not found
		if loadLockErr != nil {
			err = cli.Exit(fmt.Sprintf("Error loading/initializing %s: %v. File '%s' saved and %s updated, but lockfile operation failed. %s and %s may be inconsistent. Downloaded file '%s' is being cleaned up.", lockfile.LockfileName, loadLockErr, fullPath, config.ProjectTomlName, config.ProjectTomlName, lockfile.LockfileName, fullPath), 1)
			return
		}

		// Determine integrity hash: commit:<commit_hash> or sha256:<hash>
		var integrityHash string
		isLikelyCommitSHA := func(ref string) bool {
			if len(ref) != 40 { // Standard Git SHA-1 length
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
				if verbose {
					fmt.Printf("Using provided ref '%s' as commit SHA for lockfile hash.\\n", parsedInfo.Ref)
				}
				integrityHash = fmt.Sprintf("commit:%s", parsedInfo.Ref)
			} else {
				// Ref is likely a branch or tag, try to get the specific commit SHA
				if verbose {
					fmt.Printf("Attempting to resolve ref '%s' to a specific commit SHA for path '%s' in repo '%s/%s'...\\n", parsedInfo.Ref, parsedInfo.PathInRepo, parsedInfo.Owner, parsedInfo.Repo)
				}
				var commitSHA string
				var getCommitErr error
				commitSHA, getCommitErr = source.GetLatestCommitSHAForFile(parsedInfo.Owner, parsedInfo.Repo, parsedInfo.PathInRepo, parsedInfo.Ref)
				if getCommitErr != nil {
					if verbose {
						fmt.Printf("Warning: Failed to get specific commit SHA for '%s@%s': %v. Falling back to SHA256 content hash for lockfile.\\n", parsedInfo.PathInRepo, parsedInfo.Ref, getCommitErr)
					}
					integrityHash = fileHashSHA256
				} else {
					if verbose {
						fmt.Printf("Successfully resolved ref '%s' to commit SHA '%s'.\\n", parsedInfo.Ref, commitSHA)
					}
					integrityHash = fmt.Sprintf("commit:%s", commitSHA)
				}
			}
		} else {
			if verbose && parsedInfo.Provider == "github" {
				fmt.Printf("Insufficient information or invalid ref ('%s') to fetch specific commit SHA for GitHub source. Falling back to SHA256 content hash for lockfile.\\n", parsedInfo.Ref)
			} else if verbose {
				fmt.Printf("Source is not GitHub or ref is missing. Falling back to SHA256 content hash for lockfile.\\n")
			}
			integrityHash = fileHashSHA256 // Fallback to SHA256
		}

		// For lockfile, use the exact raw download URL and calculated integrity hash
		lf.AddOrUpdatePackage(dependencyNameInManifest, parsedInfo.RawURL, relativeDestPath, integrityHash)

		// Use a temporary variable for lockfile.Save's error
		if saveLockErr := lockfile.Save(projectRoot, lf); saveLockErr != nil {
			// Assign to named return 'err'
			err = cli.Exit(fmt.Sprintf("Error saving %s: %v. File '%s' saved and %s updated, but saving %s failed. %s and %s may be inconsistent. Downloaded file '%s' is being cleaned up.", lockfile.LockfileName, saveLockErr, fullPath, config.ProjectTomlName, lockfile.LockfileName, config.ProjectTomlName, lockfile.LockfileName, fullPath), 1) // MODIFIED
			return
		}

		if verbose {
			fmt.Printf("Successfully updated %s for dependency '%s'.\n", lockfile.LockfileName, dependencyNameInManifest)
		}

		// pnpm-style output
		_, _ = color.New(color.FgWhite).Println("Packages: +1")
		_, _ = color.New(color.FgGreen).Println("++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++") // Simple progress bar
		fmt.Println("Progress: resolved 1, downloaded 1, added 1, done")
		fmt.Println()
		_, _ = color.New(color.FgWhite, color.Bold).Println("dependencies:")
		dependencyVersionStr := parsedInfo.Ref
		if dependencyVersionStr == "" || strings.HasPrefix(dependencyVersionStr, "error:") {
			// Fallback if ref is not available or an error
			parts := strings.Split(parsedInfo.CanonicalURL, "@")
			if len(parts) > 1 {
				dependencyVersionStr = parts[len(parts)-1]
			} else {
				dependencyVersionStr = "latest" // Or some other placeholder
			}
		}
		_, _ = color.New(color.FgGreen).Printf("+ %s %s\n", dependencyNameInManifest, dependencyVersionStr)
		fmt.Println()
		duration := time.Since(startTime)
		fmt.Printf("Done in %.1fs\n", duration.Seconds())

		return nil // err is nil, so defer func() will not trigger cleanup
	},
}
