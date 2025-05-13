// Package list implements the 'list' command for displaying project dependencies and their status.
package list

import (
	"fmt"
	"os"

	"github.com/fatih/color"
	"github.com/urfave/cli/v2"

	"github.com/nightconcept/almandine/internal/core/config"
	"github.com/nightconcept/almandine/internal/core/lockfile"
	"github.com/nightconcept/almandine/internal/core/project"
)

// dependencyDisplayInfo aggregates dependency information for display formatting.
type dependencyDisplayInfo struct {
	Name           string // From project.toml
	ProjectSource  string // From project.toml
	ProjectPath    string // From project.toml
	LockedSource   string // From lockfile
	LockedHash     string // From lockfile
	FileExists     bool
	IsLocked       bool
	FileStatusInfo string // Human-readable status
}

// ListCmd returns a cli.Command that displays all project dependencies and their status.
func ListCmd() *cli.Command {
	return &cli.Command{
		Name:    "list",
		Aliases: []string{"ls"},
		Usage:   "Displays project dependencies and their status.",
		Action: func(c *cli.Context) error {
			proj, lf, err := loadListCmdData(".")
			if err != nil {
				return cli.Exit(err.Error(), 1)
			}

			displayDeps, err := collectDependencyDisplayInfo(proj, lf)
			if err != nil {
				// Errors from collectDependencyDisplayInfo are warnings, print to stderr and continue
				fmt.Fprintf(os.Stderr, "Warning during dependency collection: %v\n", err)
			}

			wd, err := os.Getwd()
			if err != nil {
				wd = "." // Fallback to current directory if Getwd fails
			}

			return printDefaultOutput(proj, displayDeps, wd)
		},
	}
}

// loadListCmdData loads the project.toml and almd-lock.toml files.
func loadListCmdData(projectDir string) (*project.Project, *lockfile.Lockfile, error) {
	proj, err := config.LoadProjectToml(projectDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil, fmt.Errorf("%s not found in %s, no project configuration loaded", config.ProjectTomlName, projectDir)
		}
		return nil, nil, fmt.Errorf("loading %s from %s: %w", config.ProjectTomlName, projectDir, err)
	}

	lf, err := lockfile.Load(projectDir)
	if err != nil {
		// If lockfile doesn't exist, it's not a fatal error for list, treat as empty.
		if os.IsNotExist(err) {
			lf = lockfile.New()
		} else {
			return nil, nil, fmt.Errorf("loading %s from %s: %w", lockfile.LockfileName, projectDir, err)
		}
	}
	if lf == nil { // Should be caught by IsNotExist, but as a safeguard.
		lf = lockfile.New()
	}
	return proj, lf, nil
}

// collectDependencyDisplayInfo gathers information for each dependency.
func collectDependencyDisplayInfo(proj *project.Project, lf *lockfile.Lockfile) ([]dependencyDisplayInfo, error) {
	var displayDeps []dependencyDisplayInfo
	var collectionErrors error // To accumulate non-fatal errors

	for name, depDetails := range proj.Dependencies {
		info := dependencyDisplayInfo{
			Name:          name,
			ProjectSource: depDetails.Source,
			ProjectPath:   depDetails.Path,
		}

		if lockEntry, ok := lf.Package[name]; ok {
			info.IsLocked = true
			info.LockedSource = lockEntry.Source
			info.LockedHash = lockEntry.Hash
		} else {
			info.IsLocked = false
			info.FileStatusInfo = "not locked"
		}

		_, statErr := os.Stat(depDetails.Path)
		if statErr == nil {
			info.FileExists = true
		} else if os.IsNotExist(statErr) {
			info.FileExists = false
			if info.FileStatusInfo != "" {
				info.FileStatusInfo += ", missing"
			} else {
				info.FileStatusInfo = "missing"
			}
		} else {
			info.FileExists = false
			if info.FileStatusInfo != "" {
				info.FileStatusInfo += ", error checking file"
			} else {
				info.FileStatusInfo = "error checking file"
			}
			// Accumulate error instead of printing directly
			err := fmt.Errorf("could not check status of %s: %w", depDetails.Path, statErr)
			if collectionErrors == nil {
				collectionErrors = err
			} else {
				collectionErrors = fmt.Errorf("%v; %w", collectionErrors, err)
			}
		}
		displayDeps = append(displayDeps, info)
	}
	return displayDeps, collectionErrors
}

// printDefaultOutput formats and prints the dependencies to standard output.
func printDefaultOutput(proj *project.Project, displayDeps []dependencyDisplayInfo, projectRootPath string) error {
	// Colors chosen for consistency with common terminal themes and accessibility:
	projectNameColor := color.New(color.FgMagenta, color.Bold, color.Underline).SprintFunc()
	projectVersionColor := color.New(color.FgMagenta).SprintFunc()
	projectPathColor := color.New(color.FgHiBlack, color.Bold, color.Underline).SprintFunc()
	dependenciesHeaderColor := color.New(color.FgCyan, color.Bold).SprintFunc()
	depNameColor := color.New(color.FgWhite).SprintFunc()
	depHashColor := color.New(color.FgYellow).SprintFunc()
	depPathColor := color.New(color.FgHiBlack).SprintFunc()

	fmt.Printf("%s@%s %s\n\n", projectNameColor(proj.Package.Name),
		projectVersionColor(proj.Package.Version),
		projectPathColor(projectRootPath))

	fmt.Println(dependenciesHeaderColor("dependencies:"))
	if len(proj.Dependencies) == 0 { // Check original proj.Dependencies, not displayDeps which might be empty due to collection errors
		fmt.Println("No dependencies found in project.toml.")
		return nil
	}
	if len(displayDeps) == 0 && len(proj.Dependencies) > 0 {
		fmt.Println("No dependencies could be processed (check warnings above).")
		return nil
	}

	for _, dep := range displayDeps {
		lockedHash := "not locked"
		if dep.IsLocked && dep.LockedHash != "" {
			lockedHash = dep.LockedHash
		} else if dep.IsLocked && dep.LockedHash == "" {
			lockedHash = "locked (no hash)"
		}

		// Potentially include dep.FileStatusInfo if it's relevant for default output
		// For now, keeping it simple as per original output.
		// If dep.FileStatusInfo is not empty, it could be appended or shown.
		// Example: fmt.Printf("%s %s %s (%s)\n", ...)

		fmt.Printf("%s %s %s\n", depNameColor(dep.Name), depHashColor(lockedHash), depPathColor(dep.ProjectPath))
	}
	return nil
}
