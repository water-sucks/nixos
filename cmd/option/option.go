package option

import (
	"encoding/json"

	"github.com/spf13/cobra"
	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
	"github.com/water-sucks/nixos/internal/logger"
)

func OptionCommand() *cobra.Command {
	opts := cmdTypes.OptionOpts{}

	cmd := cobra.Command{
		Use:   "option [flags] [NAME]",
		Short: "Query NixOS options and their details",
		Long:  "Query available NixOS module options for this system.",
		Args: func(cmd *cobra.Command, args []string) error {
			argsFunc := cobra.ExactArgs(1)
			if opts.Interactive && len(args) > 0 {
				argsFunc = cobra.MaximumNArgs(1)
			}
			if err := argsFunc(cmd, args); err != nil {
				return err
			}

			if len(args) > 0 {
				opts.OptionInput = args[0]
			}
			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			return cmdUtils.CommandErrorHandler(optionMain(cmd, &opts))
		},
	}

	cmd.Flags().BoolVarP(&opts.DisplayJson, "json", "j", false, "Output information in JSON format")
	cmd.Flags().BoolVarP(&opts.Interactive, "interactive", "i", false, "Show interactive search TUI for options")
	cmd.Flags().StringSliceVarP(&opts.NixPathIncludes, "include", "I", nil, "Add a `path` value to the Nix search path")
	cmd.Flags().BoolVarP(&opts.NoUseCache, "no-cache", "n", false, "Show interactive search TUI for options")
	cmd.Flags().BoolVarP(&opts.NoUseCache, "value-only", "v", false, "Show only the selected option's value")

	cmd.MarkFlagsMutuallyExclusive("json", "interactive", "value-only")

	cmdUtils.SetHelpFlagText(&cmd)
	cmd.SetHelpTemplate(cmd.HelpTemplate() + `
Arguments:
  [NAME]  Name of option to use. Not required in interactive mode.
`)

	return &cmd
}

func optionMain(cmd *cobra.Command, opts *cmdTypes.OptionOpts) error {
	log := logger.FromContext(cmd.Context())

	bytes, _ := json.MarshalIndent(opts, "", "  ")
	log.Infof("options: %v", string(bytes))

	return nil
}
