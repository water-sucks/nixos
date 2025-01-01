package cmd

import (
	"os"

	"github.com/spf13/cobra"
	buildVars "github.com/water-sucks/nixos/internal/build"
)

type mainOptions struct {
	ColorAlways  bool
	ConfigValues map[string]string
}

const helpTemplate = `Usage:{{if .Runnable}}
  {{.UseLine}}{{end}}{{if .HasAvailableSubCommands}}
  {{.CommandPath}} [command]{{end}}{{if gt (len .Aliases) 0}}

Aliases:
  {{.NameAndAliases}}{{end}}{{if .HasExample}}

Examples:
{{.Example}}{{end}}{{if .HasAvailableSubCommands}}{{$cmds := .Commands}}{{if eq (len .Groups) 0}}

Commands:{{range $cmds}}{{if (or .IsAvailableCommand (eq .Name "help"))}}
  {{rpad .Name .NamePadding }} {{.Short}}{{end}}{{end}}{{else}}{{range $group := .Groups}}

{{.Title}}{{range $cmds}}{{if (and (eq .GroupID $group.ID) (or .IsAvailableCommand (eq .Name "help")))}}
  {{rpad .Name .NamePadding }} {{.Short}}{{end}}{{end}}{{end}}{{if not .AllChildCommandsHaveGroup}}

Additional Commands:{{range $cmds}}{{if (and (eq .GroupID "") (or .IsAvailableCommand (eq .Name "help")))}}
  {{rpad .Name .NamePadding }} {{.Short}}{{end}}{{end}}{{end}}{{end}}{{end}}{{if .HasAvailableLocalFlags}}

Flags:
{{.LocalFlags.FlagUsages | trimTrailingWhitespaces}}{{end}}
`

func mainCommand() *cobra.Command {
	opts := mainOptions{}

	// TODO: add config, logger to context

	cmd := cobra.Command{
		Use:                        "nixos {command} [flags]",
		Short:                      "nixos-cli",
		Long:                       "A tool for managing NixOS installations",
		Version:                    buildVars.Version,
		SilenceUsage:               true,
		SuggestionsMinimumDistance: 4,
		CompletionOptions: cobra.CompletionOptions{
			HiddenDefaultCmd: true,
		},
	}

	// TODO: handle colors for error prefix

	cmd.SetErrPrefix("error:")

	cmd.SetHelpCommand(&cobra.Command{Hidden: true})
	cmd.SetUsageTemplate(helpTemplate)

	cmd.Flags().BoolP("help", "h", false, "Show this help menu")
	cmd.Flags().BoolP("version", "v", false, "Display version information")

	cmd.Flags().BoolVarP(&opts.ColorAlways, "color-always", "C", false, "Always color output when possible")
	cmd.Flags().StringToStringVarP(&opts.ConfigValues, "config", "c", map[string]string{}, "Set a configuration `key=value`")

	cmd.AddCommand(aliasesCmd())
	cmd.AddCommand(applyCmd())
	cmd.AddCommand(completionCmd())
	cmd.AddCommand(enterCmd())
	cmd.AddCommand(featuresCmd())

	return &cmd
}

func Execute() {
	if err := mainCommand().Execute(); err != nil {
		os.Exit(1)
	}
}
