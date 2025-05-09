// Title: Almandine CLI Application Entry Point
// Purpose: Initializes and runs the Almandine command-line interface application,
// defining its commands and default behavior.
package main

// Import the "fmt" package, which provides functions for formatted I/O
// (like printing to the console).
import (
	"log"
	"os"

	"github.com/urfave/cli/v2"

	"github.com/nightconcept/almandine/internal/cli/add"
	"github.com/nightconcept/almandine/internal/cli/initcmd"
	"github.com/nightconcept/almandine/internal/cli/install" // Changed from update to install
	"github.com/nightconcept/almandine/internal/cli/list"
	"github.com/nightconcept/almandine/internal/cli/remove"
	"github.com/nightconcept/almandine/internal/cli/self"
)

// version is the application version, set at build time.
var version = "dev" // Default to "dev" if not set by ldflags

// The main function, where the program execution begins.
func main() {
	app := &cli.App{
		Name:    "almd",
		Usage:   "A simple project manager for single-file dependencies",
		Version: version,
		Action: func(c *cli.Context) error {
			// Default action if no command is specified
			_ = cli.ShowAppHelp(c)
			return nil
		},
		Commands: []*cli.Command{
			initcmd.GetInitCommand(),
			add.AddCommand,
			remove.RemoveCommand(),
			install.NewInstallCommand(), // Changed from update.NewUpdateCommand()
			list.ListCmd,
			self.NewSelfCommand(),
		},
	}

	if err := app.Run(os.Args); err != nil {
		log.Fatal(err)
	}
}
