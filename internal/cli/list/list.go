// Package list implements the 'list' command for displaying project dependencies and their status.
package list

import (
	"fmt"
	"os"

	"github.com/fatih/color"
	"github.com/urfave/cli/v2"

	"github.com/nightconcept/almandine/internal/core/config"
	"github.com/nightconcept/almandine/internal/core/lockfile"
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
			projectTomlPath := "project.toml"

			proj, err := config.LoadProjectToml(".")
			if err != nil {
				if os.IsNotExist(err) {
					return cli.Exit(fmt.Sprintf("Error: %s not found. No project configuration loaded.", projectTomlPath), 1)
				}
				return cli.Exit(fmt.Sprintf("Error loading %s: %v", projectTomlPath, err), 1)
			}

			lf, err := lockfile.Load(".")
			if err != nil {
				return cli.Exit(fmt.Sprintf("Error loading %s: %v", lockfile.LockfileName, err), 1)
			}
			if lf == nil {
				lf = lockfile.New()
			}

			var displayDeps []dependencyDisplayInfo

			wd, err := os.Getwd()
			if err != nil {
				wd = "."
			}

			// Colors chosen for consistency with common terminal themes and accessibility:
			// - Magenta for project metadata (distinctive but not alarming)
			// - Yellow for hashes (conventional for references)
			// - White/Gray for general content (good readability)
			projectNameColor := color.New(color.FgMagenta, color.Bold, color.Underline).SprintFunc()
			projectVersionColor := color.New(color.FgMagenta).SprintFunc()
			projectPathColor := color.New(color.FgHiBlack, color.Bold, color.Underline).SprintFunc()
			dependenciesHeaderColor := color.New(color.FgCyan, color.Bold).SprintFunc()
			depNameColor := color.New(color.FgWhite).SprintFunc()
			depHashColor := color.New(color.FgYellow).SprintFunc()
			depPathColor := color.New(color.FgHiBlack).SprintFunc()

			fmt.Printf("%s@%s %s\n\n", projectNameColor(proj.Package.Name),
				projectVersionColor(proj.Package.Version),
				projectPathColor(wd))

			if len(proj.Dependencies) == 0 {
				fmt.Println(dependenciesHeaderColor("dependencies:"))
				fmt.Println("No dependencies found in project.toml.")
				return nil
			}

			fmt.Println(dependenciesHeaderColor("dependencies:"))
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

				if _, err := os.Stat(depDetails.Path); err == nil {
					info.FileExists = true
				} else if os.IsNotExist(err) {
					// Accumulate status messages to show all relevant issues at once
					info.FileExists = false
					if info.FileStatusInfo != "" {
						info.FileStatusInfo += ", missing"
					} else {
						info.FileStatusInfo = "missing"
					}
				} else {
					// Handle unexpected filesystem errors while preserving existing status
					info.FileExists = false
					if info.FileStatusInfo != "" {
						info.FileStatusInfo += ", error checking file"
					} else {
						info.FileStatusInfo = "error checking file"
					}
					fmt.Fprintf(os.Stderr, "Warning: could not check status of %s: %v\n", depDetails.Path, err)
				}
				displayDeps = append(displayDeps, info)
			}

			for _, dep := range displayDeps {
				// Three states for hash display:
				// - "not locked": Dependency missing from lockfile
				// - hash value: Normal case with locked dependency
				// - "locked (no hash)": Edge case where dependency is locked but hash is empty
				lockedHash := "not locked"
				if dep.IsLocked && dep.LockedHash != "" {
					lockedHash = dep.LockedHash
				} else if dep.IsLocked && dep.LockedHash == "" {
					lockedHash = "locked (no hash)"
				}

				fmt.Printf("%s %s %s\n", depNameColor(dep.Name), depHashColor(lockedHash), depPathColor(dep.ProjectPath))
			}
			return nil
		},
	}
}
