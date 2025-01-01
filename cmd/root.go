package cmd

import (
	"os"

	"github.com/spf13/cobra"
	buildVars "github.com/water-sucks/nixos/internal/build"

	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"

	aliasesCmd "github.com/water-sucks/nixos/cmd/aliases"
	applyCmd "github.com/water-sucks/nixos/cmd/apply"
	completionCmd "github.com/water-sucks/nixos/cmd/completion"
	enterCmd "github.com/water-sucks/nixos/cmd/enter"
	featuresCmd "github.com/water-sucks/nixos/cmd/features"
	generationCmd "github.com/water-sucks/nixos/cmd/generation"
	infoCmd "github.com/water-sucks/nixos/cmd/info"
)

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
{{.LocalFlags.FlagUsages | trimTrailingWhitespaces}}{{end}}{{if .HasAvailableInheritedFlags}}

Global Flags:
{{.InheritedFlags.FlagUsages | trimTrailingWhitespaces}}{{end}}
`

func mainCommand() *cobra.Command {
	opts := cmdTypes.MainOpts{}

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

	cmd.AddCommand(aliasesCmd.AliasCommand())
	cmd.AddCommand(applyCmd.ApplyCommand())
	cmd.AddCommand(completionCmd.CompletionCommand())
	cmd.AddCommand(enterCmd.EnterCommand())
	cmd.AddCommand(featuresCmd.FeatureCommand())
	cmd.AddCommand(generationCmd.GenerationCommand())
	cmd.AddCommand(infoCmd.InfoCommand())

	return &cmd
}

func Execute() {
	if err := mainCommand().Execute(); err != nil {
		os.Exit(1)
	}
}
