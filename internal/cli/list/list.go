package list

import (
	"fmt"
	"os"

	"github.com/fatih/color"
	"github.com/urfave/cli/v2"

	"github.com/nightconcept/almandine/internal/core/config"
	"github.com/nightconcept/almandine/internal/core/lockfile"
	// Assuming project root for project.toml and almd-lock.toml
)

// dependencyDisplayInfo holds all information needed for displaying a dependency.
type dependencyDisplayInfo struct {
	Name           string
	ProjectSource  string
	ProjectPath    string
	LockedSource   string
	LockedHash     string
	FileExists     bool
	IsLocked       bool   // Indicates if an entry exists in the lockfile
	FileStatusInfo string // Additional info like "missing", "not locked"
}

// ListCmd defines the structure for the 'list' command.
var ListCmd = &cli.Command{
	Name:    "list",
	Aliases: []string{"ls"},
	Usage:   "Displays project dependencies and their status.",
	Action: func(c *cli.Context) error {
		projectTomlPath := "project.toml" // This is relative to CWD, LoadProjectToml expects root

		proj, err := config.LoadProjectToml(".")
		if err != nil {
			if os.IsNotExist(err) {
				// Return an error that the test can catch, consistent with other error exits.
				// The test TestListCommand_ProjectTomlNotFound expects an error.
				return cli.Exit(fmt.Sprintf("Error: %s not found. No project configuration loaded.", projectTomlPath), 1)
			}
			// For other errors during loading
			return cli.Exit(fmt.Sprintf("Error loading %s: %v", projectTomlPath, err), 1)
		}

		lf, err := lockfile.Load(".")
		if err != nil {
			// lockfile.Load handles "not found" by returning a new lf and no error.
			// Any error here is likely a more serious issue.
			return cli.Exit(fmt.Sprintf("Error loading %s: %v", lockfile.LockfileName, err), 1)
		}
		// Ensure lf is not nil, though lockfile.Load should guarantee this if err is nil.
		if lf == nil {
			lf = lockfile.New()
		}

		var displayDeps []dependencyDisplayInfo

		// Display project information
		// Get current working directory for display, or use a placeholder if error
		wd, err := os.Getwd()
		if err != nil {
			wd = "." // Default to current directory symbol if error
		}

		// Updated Color definitions (Task 10.1, User Feedback)
		projectNameColor := color.New(color.FgMagenta, color.Bold, color.Underline).SprintFunc()
		projectVersionColor := color.New(color.FgMagenta).SprintFunc() // Version not specified for bold/underline
		projectPathColor := color.New(color.FgHiBlack, color.Bold, color.Underline).SprintFunc()
		dependenciesHeaderColor := color.New(color.FgCyan, color.Bold).SprintFunc()
		// PRD Colors for dependency line: Name (White), Hash (Yellow), Path (DimGray)
		depNameColor := color.New(color.FgWhite).SprintFunc()
		depHashColor := color.New(color.FgYellow).SprintFunc()
		depPathColor := color.New(color.FgHiBlack).SprintFunc()
		// Standard color for "@"
		atStr := "@"

		fmt.Printf("%s%s%s %s\n", projectNameColor(proj.Package.Name), atStr, projectVersionColor(proj.Package.Version), projectPathColor(wd))
		fmt.Println() // Empty line

		if len(proj.Dependencies) == 0 {
			// Handle Task 8.5: No dependencies found
			fmt.Println(dependenciesHeaderColor("dependencies:")) // Still print the header
			// Task 8.5: If project.toml has no [dependencies] table or it's empty,
			// print an appropriate message.
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

			// Check lockfile
			if lockEntry, ok := lf.Package[name]; ok {
				info.IsLocked = true
				info.LockedSource = lockEntry.Source
				info.LockedHash = lockEntry.Hash
			} else {
				info.IsLocked = false
				info.FileStatusInfo = "not locked"
			}

			// Check file existence
			// project.toml paths are relative to the project root.
			// The CWD for `almd` execution is assumed to be the project root.
			if _, err := os.Stat(depDetails.Path); err == nil {
				info.FileExists = true
			} else if os.IsNotExist(err) {
				info.FileExists = false
				if info.FileStatusInfo != "" {
					info.FileStatusInfo += ", missing"
				} else {
					info.FileStatusInfo = "missing"
				}
			} else {
				// Other error (e.g., permission denied)
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

		// Default Output Formatting (Task 8.4)
		// TODO: Add handling for --long, --json, --porcelain flags later based on PRD.
		// For now, implementing only the default format.

		// The earlier check for len(proj.Dependencies) == 0 handles the "no dependencies" case.
		// If we reach here, displayDeps should have items if proj.Dependencies had items.
		for _, dep := range displayDeps {
			lockedHash := "not locked"
			if dep.IsLocked && dep.LockedHash != "" {
				lockedHash = dep.LockedHash
			} else if dep.IsLocked && dep.LockedHash == "" {
				lockedHash = "locked (no hash)"
			}

			// PRD format: Name Hash Path
			// Apply PRD colors: Dependency Name (White), Hash (Yellow), Path (DimGray)
			fmt.Printf("%s %s %s\n", depNameColor(dep.Name), depHashColor(lockedHash), depPathColor(dep.ProjectPath))
		}
		return nil
	},
}
