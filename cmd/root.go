package cmd

import (
	"context"
	"os"

	"github.com/urfave/cli/v3"

	cmdUtils "github.com/water-sucks/nixos/internal/cmd"
)

type mainOptions struct {
	ColorAlways  bool
	ConfigValues []string
}

func mainCommand() *cli.Command {
	opts := mainOptions{}

	cmd := cli.Command{
		Name:                   "nixos",
		Usage:                  "A tool for managing NixOS installations",
		Description:            "A tool for managing NixOS installations.",
		UseShortOptionHandling: true,
		Suggest:                true,
		HideHelpCommand:        true,
		// TODO: add init code in Before
		Before: func(ctx context.Context, c *cli.Command) (context.Context, error) {
			return ctx, nil
		},
		// TODO: use version from compiled information
		Version: "0.12.0-dev",
		Flags: []cli.Flag{
			&cli.StringSliceFlag{
				Name:        "config",
				Aliases:     []string{"c"},
				Usage:       "Set a configuration value",
				Destination: &opts.ConfigValues,
				HideDefault: true,
			},
			&cli.BoolFlag{
				Name:        "color-always",
				Aliases:     []string{"C"},
				Usage:       "Always color output when possible",
				Destination: &opts.ColorAlways,
				HideDefault: true,
			},
		},
		CommandNotFound: cmdUtils.CommandNotFound,
		OnUsageError:    cmdUtils.OnUsageError,
	}

	return &cmd
}

func Execute() {
	if err := mainCommand().Run(context.Background(), os.Args); err != nil {
		os.Exit(1)
	}
}

func init() {
	defaultTemplate := `{{template "descriptionTemplate" .}}

Usage:
   {{if .UsageText}}{{wrap .UsageText 3}}{{else}}{{.FullName}} {{if .VisibleFlags}}[options]{{end}}{{if .VisibleCommands}} [command [command options]]{{end}}{{if .ArgsUsage}} {{.ArgsUsage}}{{else}}{{if .Arguments}} [arguments...]{{end}}{{end}}{{end}}{{if .VisibleCommands}}

Commands:{{template "visibleCommandCategoryTemplate" .}}{{end}}{{if .VisibleFlagCategories}}

Options:{{template "visibleFlagCategoryTemplate" .}}{{else if .VisibleFlags}}

Options:{{template "visibleFlagTemplate" .}}{{end}}
`

	cli.CommandHelpTemplate = defaultTemplate
	cli.RootCommandHelpTemplate = defaultTemplate

	cli.VersionFlag = &cli.BoolFlag{
		Name:        "version",
		Aliases:     []string{"v"},
		Usage:       "Display version information",
		HideDefault: true,
	}
	cli.HelpFlag = &cli.BoolFlag{
		Name:        "help",
		Aliases:     []string{"h"},
		Usage:       "Show this help menu",
		HideDefault: true,
	}
}
