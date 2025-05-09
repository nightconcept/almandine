package initcmd

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/nightconcept/almandine/internal/core/config"
	"github.com/nightconcept/almandine/internal/core/project"
	"github.com/urfave/cli/v2"
)

// Helper function to prompt user and get input with a default value
func promptWithDefault(reader *bufio.Reader, promptText string, defaultValue string) (string, error) {
	// Show default if not empty
	if defaultValue != "" {
		fmt.Printf("%s (default: %s): ", promptText, defaultValue)
	} else {
		fmt.Printf("%s: ", promptText)
	}

	input, err := reader.ReadString('\n')
	if err != nil {
		// Return specific error for prompt context
		return "", fmt.Errorf("failed to read input for '%s': %w", promptText, err)
	}
	input = strings.TrimSpace(input)
	if input == "" {
		return defaultValue, nil // Return default if input is empty
	}
	return input, nil
}

// GetInitCommand returns the definition for the "init" command.
func GetInitCommand() *cli.Command {
	return &cli.Command{
		Name:  "init",
		Usage: "Initialize a new Almandine project (creates project.toml)",
		Action: func(c *cli.Context) error {
			fmt.Println("Starting project initialization...")

			reader := bufio.NewReader(os.Stdin)

			var packageName, version, license, description string
			var err error

			// Prompt for package name
			packageName, err = promptWithDefault(reader, "Package name", "my-almandine-project")
			if err != nil {
				return cli.Exit(err.Error(), 1)
			}

			// Prompt for version
			version, err = promptWithDefault(reader, "Version", "0.1.0")
			if err != nil {
				return cli.Exit(err.Error(), 1)
			}

			// Prompt for license
			license, err = promptWithDefault(reader, "License", "MIT")
			if err != nil {
				return cli.Exit(err.Error(), 1)
			}

			// Prompt for description (optional, default is empty)
			description, err = promptWithDefault(reader, "Description (optional)", "")
			if err != nil {
				return cli.Exit(err.Error(), 1)
			}

			fmt.Println("\n--- Collected Metadata ---")
			fmt.Printf("Package Name: %s\n", packageName)
			fmt.Printf("Version:      %s\n", version)
			fmt.Printf("License:      %s\n", license)
			fmt.Printf("Description:  %s\n", description)
			fmt.Println("--------------------------")

			// --- Task 1.3: Implement Interactive Prompts for Scripts ---
			scripts := make(map[string]string)
			fmt.Println("\nEnter scripts (leave script name empty to finish):")

			for {
				scriptName, errLFSN := promptWithDefault(reader, "Script name", "") // Renamed err to avoid conflict
				if errLFSN != nil {
					return cli.Exit(fmt.Sprintf("Error reading script name: %v", errLFSN), 1)
				}

				if scriptName == "" {
					break
				}

				scriptCmd, errLFSC := promptWithDefault(reader, fmt.Sprintf("Command for script '%s'", scriptName), "") // Renamed err
				if errLFSC != nil {
					return cli.Exit(fmt.Sprintf("Error reading command for script '%s': %v", scriptName, errLFSC), 1)
				}
				scripts[scriptName] = scriptCmd
			}

			if _, exists := scripts["run"]; !exists {
				scripts["run"] = "lua src/main.lua"
			}

			fmt.Println("-------------------------")

			// --- Task 1.4: Implement Interactive Prompts for Dependencies (Placeholders) ---
			dependencies := make(map[string]string)
			fmt.Println("\nEnter dependencies (leave dependency name empty to finish):")

			for {
				depName, errLFDN := promptWithDefault(reader, "Dependency name", "") // Renamed err
				if errLFDN != nil {
					return cli.Exit(fmt.Sprintf("Error reading dependency name: %v", errLFDN), 1)
				}

				if depName == "" {
					break
				}

				depSource, errLFDS := promptWithDefault(reader, fmt.Sprintf("Source/Version for dependency '%s'", depName), "") // Renamed err
				if errLFDS != nil {
					return cli.Exit(fmt.Sprintf("Error reading source for dependency '%s': %v", depName, errLFDS), 1)
				}
				dependencies[depName] = depSource
			}

			fmt.Println("\n--- Collected Dependencies ---")
			if len(dependencies) > 0 {
				for name, source := range dependencies {
					fmt.Printf("%s = \"%s\"\n", name, source)
				}
			} else {
				fmt.Println("(No dependencies defined)")
			}
			fmt.Println("----------------------------")

			// Transform collected placeholder dependencies into the correct structure
			projectDependencies := make(map[string]project.Dependency)
			for name, source := range dependencies {
				projectDependencies[name] = project.Dependency{
					Source: source, // The collected placeholder string
					Path:   "",     // Path is not determined at init for placeholders
				}
			}

			// Populate the project structure
			projectData := project.Project{
				Package: &project.PackageInfo{
					Name:        packageName,
					Version:     version,
					License:     license,
					Description: description,
				},
				Scripts:      scripts,
				Dependencies: projectDependencies, // Use the transformed map
			}

			// Write to project.toml using the centralized function
			// Pass "." for current directory, as WriteProjectToml expects a directory path.
			err = config.WriteProjectToml(".", &projectData)
			if err != nil {
				return cli.Exit(fmt.Sprintf("Error writing project.toml: %v", err), 1)
			}

			fmt.Println("\nSuccessfully initialized project and wrote project.toml.")
			return nil
		},
	}
}
