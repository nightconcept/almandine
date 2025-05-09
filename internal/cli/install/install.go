package install

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/urfave/cli/v2"

	"github.com/nightconcept/almandine/internal/core/config"
	"github.com/nightconcept/almandine/internal/core/downloader"
	"github.com/nightconcept/almandine/internal/core/hasher"
	"github.com/nightconcept/almandine/internal/core/lockfile"
	"github.com/nightconcept/almandine/internal/core/source"
)

var isCommitSHARegex = regexp.MustCompile(`^[0-9a-f]{7,40}$`) // Common Git SHA lengths

// NewInstallCommand creates a new cli.Command for the "install" command.
func NewInstallCommand() *cli.Command {
	return &cli.Command{
		Name:      "install",
		Usage:     "Installs or updates project dependencies based on project.toml",
		ArgsUsage: "[dependency_names...]",
		Flags: []cli.Flag{
			&cli.BoolFlag{
				Name:    "force",
				Aliases: []string{"f"},
				Usage:   "Force install/update even if versions appear to match",
			},
			&cli.BoolFlag{
				Name:  "verbose",
				Usage: "Enable verbose output",
			},
		},
		Action: func(c *cli.Context) error {
			verbose := c.Bool("verbose")
			force := c.Bool("force") // Keep force for later use

			if verbose {
				_, _ = fmt.Fprintln(os.Stdout, "Executing 'install' command...")
				if force {
					_, _ = fmt.Fprintln(os.Stdout, "Force install/update enabled.")
				}
			}

			dependencyNames := c.Args().Slice()
			if verbose {
				if len(dependencyNames) > 0 {
					_, _ = fmt.Fprintf(os.Stdout, "Targeted dependencies for install/update: %v\n", dependencyNames)
				} else {
					_, _ = fmt.Fprintln(os.Stdout, "Targeting all dependencies for install/update.")
				}
			}

			// Load project.toml
			projCfg, err := config.LoadProjectToml(".")
			if err != nil {
				if errors.Is(err, os.ErrNotExist) {
					return cli.Exit("Error: project.toml not found in the current directory. Please run 'almd init' first.", 1)
				}
				return cli.Exit(fmt.Sprintf("Error loading project.toml: %v", err), 1)
			}
			if verbose {
				_, _ = fmt.Fprintf(os.Stdout, "Successfully loaded project.toml (Package: %s)\n", projCfg.Package.Name)
			}

			// Load almd-lock.toml
			lf, err := lockfile.Load(".")
			if err != nil {
				return cli.Exit(fmt.Sprintf("Error loading almd-lock.toml: %v", err), 1)
			}
			if verbose {
				_, _ = fmt.Fprintln(os.Stdout, "Successfully loaded or initialized almd-lock.toml.")
			}
			if lf.Package == nil {
				lf.Package = make(map[string]lockfile.PackageEntry)
			}
			if lf.ApiVersion == "" {
				lf.ApiVersion = lockfile.APIVersion
			}

			// --- Task 6.3: Dependency Iteration and Configuration Retrieval ---
			type dependencyToProcess struct {
				Name   string
				Source string
				Path   string
			}
			var dependenciesToProcessList []dependencyToProcess

			if len(dependencyNames) == 0 { // Install/update all dependencies defined in project.toml
				if len(projCfg.Dependencies) == 0 {
					_, _ = fmt.Fprintln(os.Stdout, "No dependencies found in project.toml to install/update.")
					return nil
				}
				if verbose {
					_, _ = fmt.Fprintf(os.Stdout, "Processing all %d dependencies from project.toml...\n", len(projCfg.Dependencies))
				}
				for name, depDetails := range projCfg.Dependencies {
					dependenciesToProcessList = append(dependenciesToProcessList, dependencyToProcess{
						Name:   name,
						Source: depDetails.Source,
						Path:   depDetails.Path,
					})
					if verbose {
						_, _ = fmt.Fprintf(os.Stdout, "  Targeting: %s (Source: %s, Path: %s)\n", name, depDetails.Source, depDetails.Path)
					}
				}
			} else { // Install/update specific dependencies
				if verbose {
					_, _ = fmt.Fprintf(os.Stdout, "Processing %d specified dependencies...\n", len(dependencyNames))
				}
				for _, name := range dependencyNames {
					depDetails, ok := projCfg.Dependencies[name]
					if !ok {
						_, _ = fmt.Fprintf(os.Stderr, "Warning: Dependency '%s' specified for install/update not found in project.toml. Skipping.\n", name)
						continue
					}
					dependenciesToProcessList = append(dependenciesToProcessList, dependencyToProcess{
						Name:   name,
						Source: depDetails.Source,
						Path:   depDetails.Path,
					})
					if verbose {
						_, _ = fmt.Fprintf(os.Stdout, "  Targeting: %s (Source: %s, Path: %s)\n", name, depDetails.Source, depDetails.Path)
					}
				}
				if len(dependenciesToProcessList) == 0 {
					_, _ = fmt.Fprintln(os.Stdout, "No specified dependencies were found in project.toml to install/update.")
					return nil
				}
			}

			if verbose {
				_, _ = fmt.Fprintf(os.Stdout, "Total dependencies to process: %d\n", len(dependenciesToProcessList))
			}

			// --- Task 6.4: Target Version Resolution and Lockfile State Retrieval ---
			type dependencyInstallState struct {
				Name              string
				ProjectTomlSource string // Original source string from project.toml
				ProjectTomlPath   string // Path from project.toml
				TargetRawURL      string // Resolved raw URL for download
				TargetCommitHash  string // Resolved definitive commit hash (or tag/branch if not resolvable to commit)
				LockedRawURL      string // Raw URL from almd-lock.toml
				LockedCommitHash  string // Hash from almd-lock.toml (could be commit:<sha> or sha256:<hash>)
				Provider          string
				Owner             string
				Repo              string
				PathInRepo        string
				NeedsAction       bool   // Flag to indicate if this dependency needs to be installed/updated
				ActionReason      string // Reason why an action is needed
			}
			var installStates []dependencyInstallState

			if verbose && len(dependenciesToProcessList) > 0 {
				_, _ = fmt.Fprintln(os.Stdout, "\nResolving target versions and current lock states...")
			}

			for _, depToProcess := range dependenciesToProcessList {
				if verbose {
					_, _ = fmt.Fprintf(os.Stdout, "Processing dependency: %s (Source: %s)\n", depToProcess.Name, depToProcess.Source)
				}

				parsedSourceInfo, err := source.ParseSourceURL(depToProcess.Source)
				if err != nil {
					_, _ = fmt.Fprintf(os.Stderr, "Warning: Could not parse source URL for dependency '%s' (%s): %v. Skipping.\n", depToProcess.Name, depToProcess.Source, err)
					continue
				}

				var resolvedCommitHash = parsedSourceInfo.Ref // Default to the ref from parsing
				var finalTargetRawURL = parsedSourceInfo.RawURL

				if parsedSourceInfo.Provider == "github" && !isCommitSHARegex.MatchString(parsedSourceInfo.Ref) {
					if verbose {
						_, _ = fmt.Fprintf(os.Stdout, "  Ref '%s' for '%s' is not a full commit SHA. Attempting to resolve latest commit for path '%s'...\n", parsedSourceInfo.Ref, depToProcess.Name, parsedSourceInfo.PathInRepo)
					}
					latestSHA, err := source.GetLatestCommitSHAForFile(parsedSourceInfo.Owner, parsedSourceInfo.Repo, parsedSourceInfo.PathInRepo, parsedSourceInfo.Ref)
					if err != nil {
						_, _ = fmt.Fprintf(os.Stderr, "  Warning: Could not resolve ref '%s' to a specific commit for '%s': %v. Proceeding with ref as is.\n", parsedSourceInfo.Ref, depToProcess.Name, err)
					} else {
						if verbose {
							_, _ = fmt.Fprintf(os.Stdout, "  Resolved ref '%s' to commit SHA: %s for '%s'\n", parsedSourceInfo.Ref, latestSHA, depToProcess.Name)
						}
						resolvedCommitHash = latestSHA
						finalTargetRawURL = strings.Replace(parsedSourceInfo.RawURL, "/"+parsedSourceInfo.Ref+"/", "/"+latestSHA+"/", 1)
					}
				} else if verbose && parsedSourceInfo.Provider == "github" {
					_, _ = fmt.Fprintf(os.Stdout, "  Ref '%s' for '%s' appears to be a commit SHA. Using it directly.\n", parsedSourceInfo.Ref, depToProcess.Name)
				}

				currentState := dependencyInstallState{
					Name:              depToProcess.Name,
					ProjectTomlSource: depToProcess.Source,
					ProjectTomlPath:   depToProcess.Path,
					TargetRawURL:      finalTargetRawURL,
					TargetCommitHash:  resolvedCommitHash,
					Provider:          parsedSourceInfo.Provider,
					Owner:             parsedSourceInfo.Owner,
					Repo:              parsedSourceInfo.Repo,
					PathInRepo:        parsedSourceInfo.PathInRepo,
				}

				if lockDetails, ok := lf.Package[depToProcess.Name]; ok {
					currentState.LockedRawURL = lockDetails.Source
					currentState.LockedCommitHash = lockDetails.Hash
					if verbose {
						_, _ = fmt.Fprintf(os.Stdout, "  Found in lockfile: Name: %s, Locked Source: %s, Locked Hash: %s\n", depToProcess.Name, lockDetails.Source, lockDetails.Hash)
					}
				} else {
					if verbose {
						_, _ = fmt.Fprintf(os.Stdout, "  Dependency '%s' not found in lockfile.\n", depToProcess.Name)
					}
				}
				installStates = append(installStates, currentState)
			}

			if verbose && len(installStates) > 0 {
				_, _ = fmt.Fprintln(os.Stdout, "\nFinished resolving versions. States to compare:")
				for _, s := range installStates {
					_, _ = fmt.Fprintf(os.Stdout, "  - Name: %s, TargetCommit: %s, TargetURL: %s, LockedHash: %s, LockedURL: %s\n", s.Name, s.TargetCommitHash, s.TargetRawURL, s.LockedCommitHash, s.LockedRawURL)
				}
			}

			// --- Task 6.5: Comparison Logic and Update Decision ---
			var dependenciesThatNeedAction []dependencyInstallState

			if verbose && len(installStates) > 0 {
				_, _ = fmt.Fprintln(os.Stdout, "\nDetermining which dependencies need install/update...")
			}

			for i, state := range installStates {
				reason := ""
				needsAction := false

				// 1. --force flag
				if force {
					needsAction = true
					reason = "Install/Update forced by user (--force)."
					if verbose {
						_, _ = fmt.Fprintf(os.Stdout, "  - %s: Needs install/update (forced).\n", state.Name)
					}
				}

				// 2. Dependency in project.toml but missing from almd-lock.toml
				if !needsAction && state.LockedCommitHash == "" {
					needsAction = true
					reason = "Dependency present in project.toml but not in almd-lock.toml."
					if verbose {
						_, _ = fmt.Fprintf(os.Stdout, "  - %s: Needs install/update (not in lockfile).\n", state.Name)
					}
				}

				// 3. Local file at path is missing
				if !needsAction {
					if _, err := os.Stat(state.ProjectTomlPath); errors.Is(err, os.ErrNotExist) {
						needsAction = true
						reason = fmt.Sprintf("Local file missing at path: %s.", state.ProjectTomlPath)
						if verbose {
							_, _ = fmt.Fprintf(os.Stdout, "  - %s: Needs install/update (file missing at %s).\n", state.Name, state.ProjectTomlPath)
						}
					} else if err != nil {
						_, _ = fmt.Fprintf(os.Stderr, "Warning: Could not stat file for dependency '%s' at '%s': %v. Assuming install/update check is needed.\n", state.Name, state.ProjectTomlPath, err)
						needsAction = true
						reason = fmt.Sprintf("Error checking local file status at %s: %v.", state.ProjectTomlPath, err)
					}
				}

				// 4. Resolved target commit hash differs from locked commit hash
				if !needsAction && state.TargetCommitHash != "" && state.LockedCommitHash != "" {
					var lockedSHA string
					if strings.HasPrefix(state.LockedCommitHash, "commit:") {
						lockedSHA = strings.TrimPrefix(state.LockedCommitHash, "commit:")
					}

					if lockedSHA != "" && state.TargetCommitHash != lockedSHA {
						needsAction = true
						reason = fmt.Sprintf("Target commit hash (%s) differs from locked commit hash (%s).", state.TargetCommitHash, lockedSHA)
						if verbose {
							_, _ = fmt.Fprintf(os.Stdout, "  - %s: Needs install/update (target commit %s != locked commit %s).\n", state.Name, state.TargetCommitHash, lockedSHA)
						}
					} else if lockedSHA == "" && strings.HasPrefix(state.LockedCommitHash, "sha256:") && isCommitSHARegex.MatchString(state.TargetCommitHash) {
						needsAction = true
						reason = fmt.Sprintf("Target is now a specific commit (%s), but lockfile has a content hash (%s).", state.TargetCommitHash, state.LockedCommitHash)
						if verbose {
							_, _ = fmt.Fprintf(os.Stdout, "  - %s: Needs install/update (target is specific commit %s, lockfile has content hash %s).\n", state.Name, state.TargetCommitHash, state.LockedCommitHash)
						}
					}
				}

				if needsAction {
					installStates[i].NeedsAction = true
					installStates[i].ActionReason = reason
					dependenciesThatNeedAction = append(dependenciesThatNeedAction, installStates[i])
				} else if verbose {
					_, _ = fmt.Fprintf(os.Stdout, "  - %s: Already up-to-date.\n", state.Name)
				}
			}

			if len(dependenciesThatNeedAction) == 0 {
				_, _ = fmt.Fprintln(os.Stdout, "All targeted dependencies are already up-to-date.")
				return nil
			}

			if verbose {
				_, _ = fmt.Fprintf(os.Stdout, "\nDependencies to be installed/updated (%d):\n", len(dependenciesThatNeedAction))
				for _, dep := range dependenciesThatNeedAction {
					_, _ = fmt.Fprintf(os.Stdout, "  - %s (Reason: %s)\n", dep.Name, dep.ActionReason)
				}
			}

			// --- Task 6.6: Perform Install/Update (If Required) ---
			if verbose && len(dependenciesThatNeedAction) > 0 {
				_, _ = fmt.Fprintln(os.Stdout, "\nPerforming install/update for identified dependencies...")
			}

			var successfulActions int
			for _, dep := range dependenciesThatNeedAction {
				if verbose {
					_, _ = fmt.Fprintf(os.Stdout, "  Installing/Updating '%s' from %s\n", dep.Name, dep.TargetRawURL)
				}

				fileContent, err := downloader.DownloadFile(dep.TargetRawURL)
				if err != nil {
					_, _ = fmt.Fprintf(os.Stderr, "Error: Failed to download dependency '%s' from '%s': %v\n", dep.Name, dep.TargetRawURL, err)
					continue
				}
				if verbose {
					_, _ = fmt.Fprintf(os.Stdout, "    Successfully downloaded %s (%d bytes)\n", dep.Name, len(fileContent))
				}

				var integrityHash string
				if dep.Provider == "github" && isCommitSHARegex.MatchString(dep.TargetCommitHash) {
					integrityHash = "commit:" + dep.TargetCommitHash
					if verbose {
						_, _ = fmt.Fprintf(os.Stdout, "    Using commit hash for integrity: %s\n", integrityHash)
					}
				} else {
					contentHash, err := hasher.CalculateSHA256(fileContent)
					if err != nil {
						_, _ = fmt.Fprintf(os.Stderr, "Error: Failed to calculate SHA256 hash for dependency '%s': %v\n", dep.Name, err)
						continue
					}
					integrityHash = contentHash
					if verbose {
						_, _ = fmt.Fprintf(os.Stdout, "    Calculated content hash for integrity: %s\n", integrityHash)
					}
				}

				targetDir := filepath.Dir(dep.ProjectTomlPath)
				if err := os.MkdirAll(targetDir, os.ModePerm); err != nil {
					_, _ = fmt.Fprintf(os.Stderr, "Error: Failed to create directory '%s' for dependency '%s': %v\n", targetDir, dep.Name, err)
					continue
				}
				if err := os.WriteFile(dep.ProjectTomlPath, fileContent, 0644); err != nil {
					_, _ = fmt.Fprintf(os.Stderr, "Error: Failed to write file '%s' for dependency '%s': %v\n", dep.ProjectTomlPath, dep.Name, err)
					continue
				}
				if verbose {
					_, _ = fmt.Fprintf(os.Stdout, "    Successfully saved %s to %s\n", dep.Name, dep.ProjectTomlPath)
				}

				lf.Package[dep.Name] = lockfile.PackageEntry{
					Source: dep.TargetRawURL,
					Path:   dep.ProjectTomlPath,
					Hash:   integrityHash,
				}
				if verbose {
					_, _ = fmt.Fprintf(os.Stdout, "    Updated lockfile entry for %s: Path=%s, Hash=%s, SourceURL=%s\n", dep.Name, dep.ProjectTomlPath, integrityHash, dep.TargetRawURL)
				}
				successfulActions++
			}

			if successfulActions > 0 {
				lf.ApiVersion = lockfile.APIVersion
				if err := lockfile.Save(".", lf); err != nil {
					return cli.Exit(fmt.Sprintf("Error: Failed to save updated almd-lock.toml: %v", err), 1)
				}
				if verbose {
					_, _ = fmt.Fprintf(os.Stdout, "\nSuccessfully saved almd-lock.toml with %d action(s).\n", successfulActions)
				}
				_, _ = fmt.Fprintf(os.Stdout, "Successfully installed/updated %d dependenc(ies).\n", successfulActions)
			} else {
				if len(dependenciesThatNeedAction) > 0 {
					_, _ = fmt.Fprintln(os.Stderr, "No dependencies were successfully installed/updated due to errors.")
					return cli.Exit("Install/Update process completed with errors for all targeted dependencies.", 1)
				}
			}
			return nil
		},
	}
}
