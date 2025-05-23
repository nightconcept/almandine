// Package self provides self-management functionality for the almd CLI application.
package self

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/Masterminds/semver/v3"
	"github.com/creativeprojects/go-selfupdate"
	"github.com/urfave/cli/v2"
)

// SelfCmd creates a command for managing the almd CLI application's lifecycle,
// currently supporting self-update functionality.
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

// updateAction handles the self-update process for the CLI application.
// It supports checking for and applying updates from GitHub releases.
// The function handles version comparison, user confirmation (unless --yes is specified),
// and supports custom GitHub repositories via the --source flag.
func updateAction(c *cli.Context) error {
	verbose := c.Bool("verbose")
	currentVersionStr := c.App.Version // Retain for initial parsing

	currentSemVer, err := parseVersion(currentVersionStr, verbose)
	if err != nil {
		return err // error is already a cli.Exit error
	}

	repoSlug, err := getRepoSlug(c.String("source"), verbose)
	if err != nil {
		return err // error is already a cli.Exit error
	}

	updater, err := newUpdater(verbose)
	if err != nil {
		return err // error is already a cli.Exit error
	}

	// Pass currentSemVer.String() for messages as it's validated.
	latestRelease, proceed, err := processUpdateCheck(c, currentSemVer, repoSlug, updater, verbose)
	if err != nil {
		return err // Propagate error from processUpdateCheck
	}
	if !proceed {
		return nil // Indicates no update needed, or user was informed (e.g. already latest)
	}

	// latestRelease is guaranteed non-nil if proceed is true
	return executeUpdate(c, latestRelease, updater, verbose)
}

// processUpdateCheck handles detecting the latest version, comparing it with the current version,
// and printing relevant information. It returns the latest release, a boolean indicating
// whether to proceed with the update (true if an update is available and newer), and an error if one occurred.
func processUpdateCheck(c *cli.Context, currentSemVer *semver.Version, repoSlug string, updater *selfupdate.Updater, verbose bool) (*selfupdate.Release, bool, error) {
	if verbose {
		fmt.Println("Checking for latest version...")
	}

	repository := selfupdate.ParseSlug(repoSlug)
	latestRelease, found, err := updater.DetectLatest(c.Context, repository)
	if err != nil {
		return nil, false, cli.Exit(fmt.Sprintf("Error detecting latest version: %v", err), 1)
	}

	if !found {
		if verbose {
			fmt.Println("No update available (checked with source, no newer version found).")
		}
		// Use currentSemVer.String() for consistency with other messages
		fmt.Printf("Current version %s is already the latest.\n", currentSemVer.String())
		return nil, false, nil
	}

	if verbose {
		fmt.Printf("Latest version detected: %s (Release URL: %s)\n", latestRelease.Version(), latestRelease.URL)
		if latestRelease.AssetURL != "" {
			fmt.Printf("Asset URL: %s\n", latestRelease.AssetURL)
		}
		if latestRelease.ReleaseNotes != "" {
			fmt.Printf("Release Notes:\n%s\n", latestRelease.ReleaseNotes)
		}
	}

	// Compare using currentSemVer.String() which is the parsed version string
	if !latestRelease.GreaterThan(currentSemVer.String()) {
		fmt.Printf("Current version %s is already the latest or newer.\n", currentSemVer.String())
		return nil, false, nil
	}

	fmt.Printf("New version available: %s (current: %s)\n", latestRelease.Version(), currentSemVer.String())
	return latestRelease, true, nil
}

// executeUpdate handles the confirmation and execution of the self-update.
// It assumes latestRelease is non-nil and represents an actual available update.
func executeUpdate(c *cli.Context, latestRelease *selfupdate.Release, updater *selfupdate.Updater, verbose bool) error {
	if c.Bool("check") {
		// User was already informed by processUpdateCheck that a new version is available.
		return nil
	}

	proceedConfirmation, err := confirmUpdate(c.Bool("yes"))
	if err != nil {
		// This case should ideally not be reached if confirmUpdate handles its errors properly.
		return cli.Exit(fmt.Sprintf("Error during confirmation: %v", err), 1)
	}
	if !proceedConfirmation {
		fmt.Println("Update cancelled.")
		return nil
	}

	fmt.Printf("Updating to %s...\n", latestRelease.Version())
	execPath, err := os.Executable()
	if err != nil {
		return cli.Exit(fmt.Sprintf("Could not get executable path: %v", err), 1)
	}
	if verbose {
		fmt.Printf("Current executable path: %s\n", execPath)
	}

	err = updater.UpdateTo(c.Context, latestRelease, execPath)
	if err != nil {
		return cli.Exit(fmt.Sprintf("Failed to update: %v", err), 1)
	}

	fmt.Printf("Successfully updated to version %s.\n", latestRelease.Version())
	return nil
}

// parseVersion parses the version string and returns a semver.Version.
// It handles versions with or without a 'v' prefix.
func parseVersion(versionStr string, verbose bool) (*semver.Version, error) {
	if verbose {
		fmt.Printf("almd current version: %s\n", versionStr)
	}

	v, err := semver.NewVersion(strings.TrimPrefix(versionStr, "v"))
	if err != nil {
		// Try parsing without trimming 'v' if the first attempt failed and it didn't have 'v'
		// This case is mostly defensive, as NewVersion usually handles 'v' prefix.
		if !strings.HasPrefix(versionStr, "v") {
			v, err = semver.NewVersion(versionStr)
		}
		if err != nil {
			return nil, cli.Exit(fmt.Sprintf("Error parsing current version '%s': %v. Ensure version is like vX.Y.Z or X.Y.Z.", versionStr, err), 1)
		}
	}

	if verbose {
		fmt.Printf("Parsed current semantic version: %s\n", v.String())
	}
	return v, nil
}

// getRepoSlug determines the GitHub repository slug to use for updates.
// It uses the default "nightconcept/almandine" unless a valid --source is provided.
func getRepoSlug(sourceFlag string, verbose bool) (string, error) {
	defaultRepoSlug := "nightconcept/almandine"
	repoSlug := defaultRepoSlug

	if sourceFlag != "" {
		parts := strings.Split(sourceFlag, "/")
		if len(parts) == 2 && parts[0] != "" && parts[1] != "" {
			repoSlug = sourceFlag
			if verbose {
				fmt.Printf("Using custom GitHub source: %s\n", repoSlug)
			}
		} else {
			return "", cli.Exit(fmt.Sprintf("Invalid --source format. Expected 'owner/repo', got: %s.", sourceFlag), 1)
		}
	} else {
		if verbose {
			fmt.Printf("Using default GitHub source: %s\n", repoSlug)
		}
	}
	return repoSlug, nil
}

// newUpdater creates and returns a new selfupdate.Updater instance.
func newUpdater(verbose bool) (*selfupdate.Updater, error) {
	ghSource, err := selfupdate.NewGitHubSource(selfupdate.GitHubConfig{})
	if err != nil {
		return nil, cli.Exit(fmt.Sprintf("Error creating GitHub source: %v", err), 1)
	}

	updater, err := selfupdate.NewUpdater(selfupdate.Config{
		Source: ghSource,
	})
	if err != nil {
		return nil, cli.Exit(fmt.Sprintf("Failed to initialize updater: %v", err), 1)
	}
	if verbose {
		fmt.Println("Updater initialized.")
	}
	return updater, nil
}

// confirmUpdate handles the user confirmation step for the update.
// It returns true if the user confirms or if --yes is specified, false otherwise.
func confirmUpdate(autoConfirm bool) (bool, error) {
	if autoConfirm {
		return true, nil
	}

	fmt.Print("Do you want to update? (y/N): ")
	reader := bufio.NewReader(os.Stdin)
	input, err := reader.ReadString('\n')
	if err != nil {
		// Handle potential error from ReadString, though it's often EOF or similar.
		return false, fmt.Errorf("error reading user input: %w", err)
	}

	return strings.TrimSpace(strings.ToLower(input)) == "y", nil
}
