// Package install implements the dependency installation functionality.
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
	coreproject "github.com/nightconcept/almandine/internal/core/project"
	"github.com/nightconcept/almandine/internal/core/source"
)

// isCommitSHARegex matches valid Git commit SHAs of varying lengths (7-40 chars).
// This range covers both short and full-length commit hashes.
var isCommitSHARegex = regexp.MustCompile(`^[0-9a-f]{7,40}$`)

// dependencyToProcess tracks the source configuration for each dependency
// that needs to be processed during the install/update operation.
type dependencyToProcess struct {
	Name   string
	Source string
	Path   string
}

// dependencyInstallState tracks both the target state (from project.toml) and
// current state (from lockfile) for each dependency, along with resolution details.
type dependencyInstallState struct {
	Name              string
	ProjectTomlSource string
	ProjectTomlPath   string
	TargetRawURL      string
	TargetCommitHash  string
	LockedRawURL      string
	LockedCommitHash  string
	Provider          string
	Owner             string
	Repo              string
	PathInRepo        string
	NeedsAction       bool
	ActionReason      string
}

// loadInstallConfigAndArgs loads necessary configurations and parses CLI arguments.
func loadInstallConfigAndArgs(c *cli.Context) (projCfg *coreproject.Project, lf *lockfile.Lockfile, dependencyNames []string, force bool, verbose bool, err error) {
	verbose = c.Bool("verbose")
	force = c.Bool("force")

	if verbose {
		_, _ = fmt.Fprintln(os.Stdout, "Executing 'install' command...")
		if force {
			_, _ = fmt.Fprintln(os.Stdout, "Force install/update enabled.")
		}
	}

	dependencyNames = c.Args().Slice()
	if verbose {
		if len(dependencyNames) > 0 {
			_, _ = fmt.Fprintf(os.Stdout, "Targeted dependencies for install/update: %v\n", dependencyNames)
		} else {
			_, _ = fmt.Fprintln(os.Stdout, "Targeting all dependencies for install/update.")
		}
	}

	projCfg, err = config.LoadProjectToml(".")
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, nil, nil, false, verbose, cli.Exit("Error: project.toml not found in the current directory. Please run 'almd init' first.", 1)
		}
		return nil, nil, nil, false, verbose, cli.Exit(fmt.Sprintf("Error loading project.toml: %v", err), 1)
	}
	if verbose {
		_, _ = fmt.Fprintf(os.Stdout, "Successfully loaded project.toml (Package: %s)\n", projCfg.Package.Name)
	}

	lf, err = lockfile.Load(".")
	if err != nil {
		// If lockfile doesn't exist, we initialize a new one instead of erroring out.
		// The install process will populate it.
		if errors.Is(err, os.ErrNotExist) {
			if verbose {
				_, _ = fmt.Fprintln(os.Stdout, "almd-lock.toml not found, will create a new one.")
			}
			lf = &lockfile.Lockfile{
				ApiVersion: lockfile.APIVersion,
				Package:    make(map[string]lockfile.PackageEntry),
			}
			err = nil // Clear the error as we've handled it by creating a new lockfile struct
		} else {
			return nil, nil, nil, false, verbose, cli.Exit(fmt.Sprintf("Error loading almd-lock.toml: %v", err), 1)
		}
	}

	if verbose && err == nil { // err == nil means lockfile was loaded or initialized successfully
		_, _ = fmt.Fprintln(os.Stdout, "Successfully loaded or initialized almd-lock.toml.")
	}

	if lf.Package == nil {
		lf.Package = make(map[string]lockfile.PackageEntry)
	}
	if lf.ApiVersion == "" {
		lf.ApiVersion = lockfile.APIVersion
	}
	return projCfg, lf, dependencyNames, force, verbose, nil
}

// collectDependenciesToProcess determines which dependencies to process based on arguments or all from project.toml.
func collectDependenciesToProcess(projCfg *coreproject.Project, dependencyNames []string, verbose bool) ([]dependencyToProcess, error) {
	var dependenciesToProcessList []dependencyToProcess

	if len(dependencyNames) == 0 {
		if len(projCfg.Dependencies) == 0 {
			_, _ = fmt.Fprintln(os.Stdout, "No dependencies found in project.toml to install/update.")
			return nil, nil // Return nil, nil to indicate no error but no work
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
	} else {
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
			return nil, nil // Return nil, nil to indicate no error but no work
		}
	}

	if verbose {
		_, _ = fmt.Fprintf(os.Stdout, "Total dependencies to process: %d\n", len(dependenciesToProcessList))
	}
	return dependenciesToProcessList, nil
}

// resolveGitHubCommitRef attempts to resolve a Git ref (branch/tag) to a specific commit SHA for GitHub sources.
// If the ref is already a SHA, or resolution fails, it returns the original ref and URL.
func resolveGitHubCommitRef(parsedSourceInfo *source.ParsedSourceInfo, depName string, verbose bool) (resolvedCommitHash string, finalTargetRawURL string) {
	resolvedCommitHash = parsedSourceInfo.Ref
	finalTargetRawURL = parsedSourceInfo.RawURL

	if parsedSourceInfo.Provider == "github" && !isCommitSHARegex.MatchString(parsedSourceInfo.Ref) {
		if verbose {
			_, _ = fmt.Fprintf(os.Stdout, "  Ref '%s' for '%s' is not a full commit SHA. Attempting to resolve latest commit for path '%s'...\n", parsedSourceInfo.Ref, depName, parsedSourceInfo.PathInRepo)
		}
		latestSHA, err := source.GetLatestCommitSHAForFile(parsedSourceInfo.Owner, parsedSourceInfo.Repo, parsedSourceInfo.PathInRepo, parsedSourceInfo.Ref)
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "  Warning: Could not resolve ref '%s' to a specific commit for '%s': %v. Proceeding with ref as is.\n", parsedSourceInfo.Ref, depName, err)
		} else {
			if verbose {
				_, _ = fmt.Fprintf(os.Stdout, "  Resolved ref '%s' to commit SHA: %s for '%s'\n", parsedSourceInfo.Ref, latestSHA, depName)
			}
			resolvedCommitHash = latestSHA
			finalTargetRawURL = strings.Replace(parsedSourceInfo.RawURL, "/"+parsedSourceInfo.Ref+"/", "/"+latestSHA+"/", 1)
		}
	} else if verbose && parsedSourceInfo.Provider == "github" {
		_, _ = fmt.Fprintf(os.Stdout, "  Ref '%s' for '%s' appears to be a commit SHA. Using it directly.\n", parsedSourceInfo.Ref, depName)
	}
	return resolvedCommitHash, finalTargetRawURL
}

// resolveSingleDependencyState resolves the target and locked state for a single dependency.
func resolveSingleDependencyState(depToProcess dependencyToProcess, lf *lockfile.Lockfile, verbose bool) (*dependencyInstallState, error) {
	if verbose {
		_, _ = fmt.Fprintf(os.Stdout, "Processing dependency: %s (Source: %s)\n", depToProcess.Name, depToProcess.Source)
	}

	parsedSourceInfo, err := source.ParseSourceURL(depToProcess.Source)
	if err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "Warning: Could not parse source URL for dependency '%s' (%s): %v. Skipping.\n", depToProcess.Name, depToProcess.Source, err)
		return nil, nil // Return nil, nil to indicate skipping this dependency
	}

	resolvedCommitHash, finalTargetRawURL := resolveGitHubCommitRef(parsedSourceInfo, depToProcess.Name, verbose)

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
	return &currentState, nil
}

// resolveInstallStates resolves the target and locked states for each dependency.
func resolveInstallStates(dependenciesToProcessList []dependencyToProcess, lf *lockfile.Lockfile, verbose bool) ([]dependencyInstallState, error) {
	var installStates []dependencyInstallState

	if verbose && len(dependenciesToProcessList) > 0 {
		_, _ = fmt.Fprintln(os.Stdout, "\nResolving target versions and current lock states...")
	}

	for _, depToProcess := range dependenciesToProcessList {
		state, err := resolveSingleDependencyState(depToProcess, lf, verbose)
		if err != nil {
			// This error case is not currently hit by resolveSingleDependencyState as it returns nil, nil for skippable errors.
			// However, keeping it for future robustness if resolveSingleDependencyState changes to return actual errors.
			_, _ = fmt.Fprintf(os.Stderr, "Error resolving state for dependency '%s': %v. Skipping.\n", depToProcess.Name, err)
			continue
		}
		if state != nil {
			installStates = append(installStates, *state)
		}
	}

	if verbose && len(installStates) > 0 {
		_, _ = fmt.Fprintln(os.Stdout, "\nFinished resolving versions. States to compare:")
		for _, s := range installStates {
			_, _ = fmt.Fprintf(os.Stdout, "  - Name: %s, TargetCommit: %s, TargetURL: %s, LockedHash: %s, LockedURL: %s\n", s.Name, s.TargetCommitHash, s.TargetRawURL, s.LockedCommitHash, s.LockedRawURL)
		}
	}
	return installStates, nil
}

// filterDependenciesRequiringAction identifies which dependencies actually need an install/update.

func checkForceInstall(state dependencyInstallState, force bool, verbose bool) (needsAction bool, reason string) {
	if force {
		if verbose {
			_, _ = fmt.Fprintf(os.Stdout, "  - %s: Needs install/update (forced).\n", state.Name)
		}
		return true, "Install/Update forced by user (--force)."
	}
	return false, ""
}

func checkMissingFromLockfile(state dependencyInstallState, verbose bool) (needsAction bool, reason string) {
	if state.LockedCommitHash == "" {
		if verbose {
			_, _ = fmt.Fprintf(os.Stdout, "  - %s: Needs install/update (not in lockfile).\n", state.Name)
		}
		return true, "Dependency present in project.toml but not in almd-lock.toml."
	}
	return false, ""
}

func checkLocalFileStatus(state dependencyInstallState, verbose bool) (needsAction bool, reason string) {
	if _, err := os.Stat(state.ProjectTomlPath); errors.Is(err, os.ErrNotExist) {
		if verbose {
			_, _ = fmt.Fprintf(os.Stdout, "  - %s: Needs install/update (file missing at %s).\n", state.Name, state.ProjectTomlPath)
		}
		return true, fmt.Sprintf("Local file missing at path: %s.", state.ProjectTomlPath)
	} else if err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "Warning: Could not stat file for dependency '%s' at '%s': %v. Assuming install/update check is needed.\n", state.Name, state.ProjectTomlPath, err)
		return true, fmt.Sprintf("Error checking local file status at %s: %v.", state.ProjectTomlPath, err)
	}
	return false, ""
}

func checkCommitHashMismatch(state dependencyInstallState, verbose bool) (needsAction bool, reason string) {
	if state.TargetCommitHash == "" || state.LockedCommitHash == "" {
		return false, ""
	}
	var lockedSHA string
	if strings.HasPrefix(state.LockedCommitHash, "commit:") {
		lockedSHA = strings.TrimPrefix(state.LockedCommitHash, "commit:")
	}

	if lockedSHA != "" && state.TargetCommitHash != lockedSHA {
		if verbose {
			_, _ = fmt.Fprintf(os.Stdout, "  - %s: Needs install/update (target commit %s != locked commit %s).\n", state.Name, state.TargetCommitHash, lockedSHA)
		}
		return true, fmt.Sprintf("Target commit hash (%s) differs from locked commit hash (%s).", state.TargetCommitHash, lockedSHA)
	}
	return false, ""
}

func checkHashTypeConflict(state dependencyInstallState, verbose bool) (needsAction bool, reason string) {
	if state.TargetCommitHash == "" || state.LockedCommitHash == "" {
		return false, ""
	}
	var lockedSHA string
	if strings.HasPrefix(state.LockedCommitHash, "commit:") {
		lockedSHA = strings.TrimPrefix(state.LockedCommitHash, "commit:")
	}

	if lockedSHA == "" && strings.HasPrefix(state.LockedCommitHash, "sha256:") && isCommitSHARegex.MatchString(state.TargetCommitHash) {
		if verbose {
			_, _ = fmt.Fprintf(os.Stdout, "  - %s: Needs install/update (target is specific commit %s, lockfile has content hash %s).\n", state.Name, state.TargetCommitHash, state.LockedCommitHash)
		}
		return true, fmt.Sprintf("Target is now a specific commit (%s), but lockfile has a content hash (%s).", state.TargetCommitHash, state.LockedCommitHash)
	}
	return false, ""
}

func filterDependenciesRequiringAction(installStates []dependencyInstallState, force bool, verbose bool) []dependencyInstallState {
	var dependenciesThatNeedAction []dependencyInstallState

	if verbose && len(installStates) > 0 {
		_, _ = fmt.Fprintln(os.Stdout, "\nDetermining which dependencies need install/update...")
	}

	for _, state := range installStates {
		var needsAction bool
		var reason string

		if needsAction, reason = checkForceInstall(state, force, verbose); needsAction {
			// Already determined action
		} else if needsAction, reason = checkMissingFromLockfile(state, verbose); needsAction {
			// Already determined action
		} else if needsAction, reason = checkLocalFileStatus(state, verbose); needsAction {
			// Already determined action
		} else if needsAction, reason = checkCommitHashMismatch(state, verbose); needsAction {
			// Already determined action
		} else {
			// If none of the previous conditions were met, check the last one.
			// The assignment happens regardless, but we only enter the 'if needsAction' block below if one of the checks returned true.
			needsAction, reason = checkHashTypeConflict(state, verbose)
		}

		if needsAction {
			actionableState := state // Make a copy
			actionableState.NeedsAction = true
			actionableState.ActionReason = reason
			dependenciesThatNeedAction = append(dependenciesThatNeedAction, actionableState)
		} else if verbose {
			_, _ = fmt.Fprintf(os.Stdout, "  - %s: Already up-to-date.\n", state.Name)
		}
	}
	return dependenciesThatNeedAction
}

// executeSingleInstallOperation handles the installation process for a single dependency.
// It returns the new lockfile entry and a boolean indicating success.
func executeSingleInstallOperation(dep dependencyInstallState, verbose bool) (*lockfile.PackageEntry, bool) {
	if verbose {
		_, _ = fmt.Fprintf(os.Stdout, "  Installing/Updating '%s' from %s\n", dep.Name, dep.TargetRawURL)
	}

	fileContent, downloadErr := downloader.DownloadFile(dep.TargetRawURL)
	if downloadErr != nil {
		_, _ = fmt.Fprintf(os.Stderr, "Error: Failed to download dependency '%s' from '%s': %v\n", dep.Name, dep.TargetRawURL, downloadErr)
		return nil, false
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
		contentHash, hashErr := hasher.CalculateSHA256(fileContent)
		if hashErr != nil {
			_, _ = fmt.Fprintf(os.Stderr, "Error: Failed to calculate SHA256 hash for dependency '%s': %v\n", dep.Name, hashErr)
			return nil, false
		}
		integrityHash = contentHash
		if verbose {
			_, _ = fmt.Fprintf(os.Stdout, "    Calculated content hash for integrity: %s\n", integrityHash)
		}
	}

	targetDir := filepath.Dir(dep.ProjectTomlPath)
	if mkdirErr := os.MkdirAll(targetDir, os.ModePerm); mkdirErr != nil {
		_, _ = fmt.Fprintf(os.Stderr, "Error: Failed to create directory '%s' for dependency '%s': %v\n", targetDir, dep.Name, mkdirErr)
		return nil, false
	}
	if writeErr := os.WriteFile(dep.ProjectTomlPath, fileContent, 0644); writeErr != nil {
		_, _ = fmt.Fprintf(os.Stderr, "Error: Failed to write file '%s' for dependency '%s': %v\n", dep.ProjectTomlPath, dep.Name, writeErr)
		return nil, false
	}
	if verbose {
		_, _ = fmt.Fprintf(os.Stdout, "    Successfully saved %s to %s\n", dep.Name, dep.ProjectTomlPath)
	}

	newEntry := lockfile.PackageEntry{
		Source: dep.TargetRawURL,
		Path:   dep.ProjectTomlPath,
		Hash:   integrityHash,
	}
	if verbose {
		_, _ = fmt.Fprintf(os.Stdout, "    Prepared lockfile entry for %s: Path=%s, Hash=%s, SourceURL=%s\n", dep.Name, newEntry.Path, newEntry.Hash, newEntry.Source)
	}
	return &newEntry, true
}

// executeInstallOperations performs the download, hashing, file saving, and lockfile data updates.
func executeInstallOperations(dependenciesThatNeedAction []dependencyInstallState, lf *lockfile.Lockfile, verbose bool) (successfulActions int, err error) {
	if verbose && len(dependenciesThatNeedAction) > 0 {
		_, _ = fmt.Fprintln(os.Stdout, "\nPerforming install/update for identified dependencies...")
	}

	for _, dep := range dependenciesThatNeedAction {
		newLockEntry, success := executeSingleInstallOperation(dep, verbose)
		if success && newLockEntry != nil {
			lf.Package[dep.Name] = *newLockEntry
			if verbose {
				_, _ = fmt.Fprintf(os.Stdout, "    Updated lockfile for %s.\n", dep.Name)
			}
			successfulActions++
		} else {
			// Error message already printed by executeSingleInstallOperation
			if verbose {
				_, _ = fmt.Fprintf(os.Stdout, "    Failed to process %s.\n", dep.Name)
			}
		}
	}
	return successfulActions, nil
}

// InstallCmd creates a new install command that handles dependency management.
func InstallCmd() *cli.Command {
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
			projCfg, lf, dependencyNames, force, verbose, err := loadInstallConfigAndArgs(c)
			if err != nil {
				return err // Error is already a cli.Exit
			}

			dependenciesToProcessList, err := collectDependenciesToProcess(projCfg, dependencyNames, verbose)
			if err != nil {
				return cli.Exit(fmt.Sprintf("Error collecting dependencies to process: %v", err), 1)
			}
			if dependenciesToProcessList == nil { // Indicates no work to do, message already printed
				return nil
			}

			installStates, err := resolveInstallStates(dependenciesToProcessList, lf, verbose)
			if err != nil {
				return cli.Exit(fmt.Sprintf("Error resolving dependency states: %v", err), 1)
			}

			dependenciesThatNeedAction := filterDependenciesRequiringAction(installStates, force, verbose)

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

			successfulActions, err := executeInstallOperations(dependenciesThatNeedAction, lf, verbose)
			if err != nil {
				// This error isn't currently returned by executeInstallOperations but good for future proofing
				return cli.Exit(fmt.Sprintf("Critical error during install operations: %v", err), 1)
			}

			if successfulActions > 0 {
				lf.ApiVersion = lockfile.APIVersion // Ensure API version is set
				if err := lockfile.Save(".", lf); err != nil {
					return cli.Exit(fmt.Sprintf("Error: Failed to save updated almd-lock.toml: %v", err), 1)
				}
				if verbose {
					_, _ = fmt.Fprintf(os.Stdout, "\nSuccessfully saved almd-lock.toml with %d action(s).\n", successfulActions)
				}
				_, _ = fmt.Fprintf(os.Stdout, "Successfully installed/updated %d dependenc(ies).\n", successfulActions)
			} else {
				if len(dependenciesThatNeedAction) > 0 { // Implies all actions failed
					_, _ = fmt.Fprintln(os.Stderr, "No dependencies were successfully installed/updated due to errors.")
					return cli.Exit("Install/Update process completed with errors for all targeted dependencies.", 1)
				}
				// If dependenciesThatNeedAction was empty, this path shouldn't be reached due to earlier check.
			}
			return nil
		},
	}
}
