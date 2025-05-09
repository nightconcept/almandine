package self

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/Masterminds/semver/v3" // Corrected semver import
	"github.com/creativeprojects/go-selfupdate"

	// No separate source import needed for basic GitHub
	"github.com/urfave/cli/v2"
)

// SelfCmd creates a new command for self-management.
func SelfCmd() *cli.Command {
	return &cli.Command{
		Name:  "self",
		Usage: "Manage the almd CLI application itself",
		Subcommands: []*cli.Command{
			{
				Name:  "update",
				Usage: "Update almd to the latest version",
				Flags: []cli.Flag{
					&cli.BoolFlag{
						Name:    "yes",
						Aliases: []string{"y"},
						Usage:   "Automatically confirm the update",
					},
					&cli.BoolFlag{
						Name:  "check",
						Usage: "Check for available updates without installing",
					},
					&cli.StringFlag{
						Name:  "source",
						Usage: "Specify a custom GitHub update source as 'owner/repo' (e.g., 'nightconcept/almandine')",
					},
					&cli.BoolFlag{
						Name:  "verbose",
						Usage: "Enable verbose output",
					},
				},
				Action: updateAction,
			},
		},
	}
}

func updateAction(c *cli.Context) error {
	currentVersionStr := c.App.Version
	verbose := c.Bool("verbose")

	if verbose {
		fmt.Printf("almd current version: %s\n", currentVersionStr)
	}

	currentSemVer, err := semver.NewVersion(strings.TrimPrefix(currentVersionStr, "v"))
	if err != nil {
		// Try parsing without 'v' if the first attempt failed and it didn't have 'v'
		if !strings.HasPrefix(currentVersionStr, "v") {
			currentSemVer, err = semver.NewVersion(currentVersionStr)
		}
		if err != nil {
			return cli.Exit(fmt.Sprintf("Error parsing current version '%s': %v. Ensure version is like vX.Y.Z or X.Y.Z.", currentVersionStr, err), 1)
		}
	}
	if verbose {
		fmt.Printf("Parsed current semantic version: %s\n", currentSemVer.String())
	}

	sourceFlag := c.String("source")
	repoSlug := "nightconcept/almandine" // Default repository

	if sourceFlag != "" {
		parts := strings.Split(sourceFlag, "/")
		if len(parts) == 2 && parts[0] != "" && parts[1] != "" {
			repoSlug = sourceFlag
			if verbose {
				fmt.Printf("Using custom GitHub source: %s\n", repoSlug)
			}
		} else {
			return cli.Exit(fmt.Sprintf("Invalid --source format. Expected 'owner/repo', got: %s.", sourceFlag), 1)
		}
	} else {
		if verbose {
			fmt.Printf("Using default GitHub source: %s\n", repoSlug)
		}
	}

	// For standard GitHub, GitHubConfig can be empty.
	// For GitHub Enterprise, EnterpriseBaseURL would be set here.
	ghSource, err := selfupdate.NewGitHubSource(selfupdate.GitHubConfig{})
	if err != nil {
		return cli.Exit(fmt.Sprintf("Error creating GitHub source: %v", err), 1)
	}

	updater, err := selfupdate.NewUpdater(selfupdate.Config{
		Source: ghSource,
	})
	if err != nil {
		return cli.Exit(fmt.Sprintf("Failed to initialize updater: %v", err), 1)
	}

	if verbose {
		fmt.Println("Checking for latest version...")
	}

	// DetectLatest takes a Repository object, created by ParseSlug
	repository := selfupdate.ParseSlug(repoSlug)
	latestRelease, found, err := updater.DetectLatest(c.Context, repository)
	if err != nil {
		// An actual error occurred during detection
		return cli.Exit(fmt.Sprintf("Error detecting latest version: %v", err), 1)
	}

	if !found {
		// No update was found, and no error occurred.
		if verbose {
			fmt.Println("No update available (checked with source, no newer version found).")
		}
		fmt.Printf("Current version %s is already the latest.\n", currentVersionStr)
		return nil
	}

	// If found is true, latestRelease is populated.
	// latestRelease.Version() returns string, latestRelease.version is *semver.Version
	if verbose {
		fmt.Printf("Latest version detected: %s (Release URL: %s)\n", latestRelease.Version(), latestRelease.URL)
		if latestRelease.AssetURL != "" {
			fmt.Printf("Asset URL: %s\n", latestRelease.AssetURL)
		}
		if latestRelease.ReleaseNotes != "" { // Accessing ReleaseNotes directly
			fmt.Printf("Release Notes:\n%s\n", latestRelease.ReleaseNotes)
		}
	}

	// Compare using the internal *semver.Version objects
	// The selfupdate.Release struct has methods like GreaterThan(string).
	// currentSemVer is a *semver.Version, so we use its string representation for the comparison.
	if !latestRelease.GreaterThan(currentSemVer.String()) {
		fmt.Printf("Current version %s is already the latest or newer.\n", currentVersionStr)
		return nil
	}

	fmt.Printf("New version available: %s (current: %s)\n", latestRelease.Version(), currentVersionStr)

	if c.Bool("check") {
		return nil
	}

	if !c.Bool("yes") {
		fmt.Print("Do you want to update? (y/N): ")
		reader := bufio.NewReader(os.Stdin)
		input, _ := reader.ReadString('\n')
		if strings.TrimSpace(strings.ToLower(input)) != "y" {
			fmt.Println("Update cancelled.")
			return nil
		}
	}

	fmt.Printf("Updating to %s...\n", latestRelease.Version())
	execPath, err := os.Executable()
	if err != nil {
		return cli.Exit(fmt.Sprintf("Could not get executable path: %v", err), 1)
	}
	if verbose {
		fmt.Printf("Current executable path: %s\n", execPath)
	}

	// The UpdateTo method expects a *Release object
	err = updater.UpdateTo(c.Context, latestRelease, execPath)
	if err != nil {
		return cli.Exit(fmt.Sprintf("Failed to update: %v", err), 1)
	}

	fmt.Printf("Successfully updated to version %s.\n", latestRelease.Version())
	return nil
}
