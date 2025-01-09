package cmd

import (
	"context"
	"fmt"
	"os"

	"github.com/fatih/color"
	"github.com/spf13/cobra"
	buildVars "github.com/water-sucks/nixos/internal/build"
	"github.com/water-sucks/nixos/internal/config"
	"github.com/water-sucks/nixos/internal/constants"
	"github.com/water-sucks/nixos/internal/logger"

	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"

	aliasesCmd "github.com/water-sucks/nixos/cmd/aliases"
	applyCmd "github.com/water-sucks/nixos/cmd/apply"
	completionCmd "github.com/water-sucks/nixos/cmd/completion"
	enterCmd "github.com/water-sucks/nixos/cmd/enter"
	featuresCmd "github.com/water-sucks/nixos/cmd/features"
	generationCmd "github.com/water-sucks/nixos/cmd/generation"
	infoCmd "github.com/water-sucks/nixos/cmd/info"
	initCmd "github.com/water-sucks/nixos/cmd/init"
	installCmd "github.com/water-sucks/nixos/cmd/install"
	manualCmd "github.com/water-sucks/nixos/cmd/manual"
	optionCmd "github.com/water-sucks/nixos/cmd/option"
	replCmd "github.com/water-sucks/nixos/cmd/repl"
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
{{.LocalFlags.FlagUsages | trimTrailingWhitespaces}}{{end}}
`

func mainCommand() (*cobra.Command, error) {
	opts := cmdTypes.MainOpts{}

	log := logger.NewLogger()
	cmdCtx := logger.WithLogger(context.Background(), log)

	configLocation := os.Getenv("NIXOS_CLI_CONFIG")
	if configLocation == "" {
		configLocation = constants.DefaultConfigLocation
	}

	cfg, err := config.ParseConfig(configLocation)
	if err != nil {
		log.Error(err)
		log.Warn("proceeding with defaults only, you have been warned")
		cfg = config.NewConfig()
	}

	errs := cfg.Validate()
	for _, err := range errs {
		log.Warn(err.Error())
	}

	cmdCtx = config.WithConfig(cmdCtx, cfg)

	cmd := cobra.Command{
		Use:                        "nixos {command} [flags]",
		Short:                      "nixos-cli",
		Long:                       "A tool for managing NixOS installations",
		Version:                    buildVars.Version,
		SilenceUsage:               true,
		SuggestionsMinimumDistance: 1,
		CompletionOptions: cobra.CompletionOptions{
			HiddenDefaultCmd: true,
		},
		PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
			for key, value := range opts.ConfigValues {
				err := cfg.SetValue(key, value)
				if err != nil {
					return fmt.Errorf("failed to set %v: %w", key, err)
				}
			}

			errs := cfg.Validate()
			for _, err := range errs {
				log.Warn(err.Error())
			}

			// Now that we have the real color settings from parsing
			// the configuration and command-line arguments, set it.
			//
			// Precedence of color settings:
			// 1. -C flag -> true
			// 2. NO_COLOR=1 -> false, fatih/color already takes this into account
			// 3. `color` setting from config (default: true)
			if opts.ColorAlways {
				color.NoColor = false
				log.RefreshColorPrefixes()
			} else if os.Getenv("NO_COLOR") == "" {
				color.NoColor = !cfg.UseColor
				log.RefreshColorPrefixes()
			}

			return nil
		},
	}

	cmd.SetContext(cmdCtx)

	cmd.SetErrPrefix(color.RedString("error:"))

	cmd.SetHelpCommand(&cobra.Command{Hidden: true})
	cmd.SetUsageTemplate(helpTemplate)

	cmd.Flags().BoolP("help", "h", false, "Show this help menu")
	cmd.Flags().BoolP("version", "v", false, "Display version information")

	cmd.PersistentFlags().BoolVar(&opts.ColorAlways, "color-always", false, "Always color output when possible")
	cmd.PersistentFlags().StringToStringVar(&opts.ConfigValues, "config", map[string]string{}, "Set a configuration `key=value`")

	err = cmd.RegisterFlagCompletionFunc("config", config.CompleteConfigFlag)
	if err != nil {
		return nil, err
	}

	cmd.AddCommand(aliasesCmd.AliasCommand())
	cmd.AddCommand(applyCmd.ApplyCommand(cfg))
	cmd.AddCommand(completionCmd.CompletionCommand())
	cmd.AddCommand(enterCmd.EnterCommand())
	cmd.AddCommand(featuresCmd.FeatureCommand())
	cmd.AddCommand(generationCmd.GenerationCommand())
	cmd.AddCommand(infoCmd.InfoCommand())
	cmd.AddCommand(initCmd.InitCommand())
	cmd.AddCommand(installCmd.InstallCommand())
	cmd.AddCommand(manualCmd.ManualCommand())
	cmd.AddCommand(optionCmd.OptionCommand())
	cmd.AddCommand(replCmd.ReplCommand())

	return &cmd, nil
}

func Execute() {
	cmd, err := mainCommand()
	if err != nil {
		os.Exit(1)
	}

	if err = cmd.Execute(); err != nil {
		os.Exit(1)
	}
}
