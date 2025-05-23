package main

import (
	"log"
	"os"

	"github.com/urfave/cli/v2"

	"github.com/nightconcept/almandine/internal/cli/add"
	initcmd "github.com/nightconcept/almandine/internal/cli/init"
	"github.com/nightconcept/almandine/internal/cli/install"
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
		Usage:   "Lua package manager for single-file dependencies",
		Version: version,
		Action: func(c *cli.Context) error {
			// Default action if no command is specified
			_ = cli.ShowAppHelp(c)
			return nil
		},
		Commands: []*cli.Command{
			initcmd.InitCmd(),
			add.AddCmd(),
			remove.RemoveCmd(),
			install.InstallCmd(),
			list.ListCmd(),
			self.SelfCmd(),
		},
	}

	if err := app.Run(os.Args); err != nil {
		log.Fatal(err)
	}
}
