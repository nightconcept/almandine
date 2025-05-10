package init

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/nightconcept/almandine/internal/core/config"
	"github.com/nightconcept/almandine/internal/core/project"
	"github.com/urfave/cli/v2"
)

// promptWithDefault asks the user for input and returns the entered value or a default if input is empty.
// Returns an error if reading input fails.
func promptWithDefault(reader *bufio.Reader, promptText string, defaultValue string) (string, error) {
	if defaultValue != "" {
		fmt.Printf("%s (default: %s): ", promptText, defaultValue)
	} else {
		fmt.Printf("%s: ", promptText)
	}

	input, err := reader.ReadString('\n')
	if err != nil {
		return "", fmt.Errorf("failed to read input for '%s': %w", promptText, err)
	}
	input = strings.TrimSpace(input)
	if input == "" {
		return defaultValue, nil
	}
	return input, nil
}

// InitCmd returns the definition for the "init" command.
func InitCmd() *cli.Command {
	return &cli.Command{
		Name:  "init",
		Usage: "Initialize a new Almandine project (creates project.toml)",
		Action: func(c *cli.Context) error {
			fmt.Println("Starting project initialization...")

			reader := bufio.NewReader(os.Stdin)

			var packageName, version, license, description string
			var err error

			packageName, err = promptWithDefault(reader, "Package name", "my-almandine-project")
			if err != nil {
				return cli.Exit(err.Error(), 1)
			}

			version, err = promptWithDefault(reader, "Version", "0.1.0")
			if err != nil {
				return cli.Exit(err.Error(), 1)
			}

			license, err = promptWithDefault(reader, "License", "MIT")
			if err != nil {
				return cli.Exit(err.Error(), 1)
			}

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

			scripts := make(map[string]string)

			if _, exists := scripts["run"]; !exists {
				scripts["run"] = "lua src/main.lua"
			}

			projectData := project.Project{
				Package: &project.PackageInfo{
					Name:        packageName,
					Version:     version,
					License:     license,
					Description: description,
				},
				Scripts: scripts,
			}

			err = config.WriteProjectToml(".", &projectData)
			if err != nil {
				return cli.Exit(fmt.Sprintf("Error writing project.toml: %v", err), 1)
			}

			fmt.Println("\nSuccessfully initialized project and wrote project.toml.")
			return nil
		},
	}
}
