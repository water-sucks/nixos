package cmd

import (
	"encoding/json"

	"github.com/spf13/cobra"

	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
	"github.com/water-sucks/nixos/internal/logger"
)

func EnterCommand() *cobra.Command {
	opts := cmdTypes.EnterOpts{}

	cmd := cobra.Command{
		Use:   "enter [flags] [-- ARGS...]",
		Short: "Chroot into a NixOS installation",
		Long:  "Enter a NixOS chroot environment.",
		PreRunE: func(cmd *cobra.Command, args []string) error {
			if len(args) > 0 {
				opts.CommandArray = args
			}
			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			return cmdUtils.CommandErrorHandler(enterMain(cmd, &opts))
		},
	}

	cmd.Flags().StringVarP(&opts.Command, "command", "c", "", "Command `string` to execute in bash")
	cmd.Flags().StringVarP(&opts.RootLocation, "root", "r", "/mnt", "NixOS system root `path` to enter")
	cmd.Flags().StringVar(&opts.System, "system", "", "NixOS system configuration to activate at `path`")
	cmd.Flags().BoolVarP(&opts.Silent, "silent", "s", false, "Suppress all system activation output")
	cmd.Flags().BoolVarP(&opts.Verbose, "verbose", "v", false, "Show verbose logging")

	cmd.MarkFlagsMutuallyExclusive("silent", "verbose")

	cmdUtils.SetHelpFlagText(&cmd)
	cmd.SetHelpTemplate(cmd.HelpTemplate() + `
Arguments:
  [ARGS...]  Interpret arguments as the command to run directly

If providing a command through positional arguments with flags, a preceding
double dash (--) is required. Otherwise, unexpected behavior may occur.
`)

	return &cmd
}

func enterMain(cmd *cobra.Command, opts *cmdTypes.EnterOpts) error {
	log := logger.FromContext(cmd.Context())

	if len(opts.CommandArray) > 0 && len(opts.Command) > 1 {
		log.Warn("preferring --command flag over positional args, both were specified")
	}

	bytes, _ := json.MarshalIndent(opts, "", "  ")
	log.Infof("enter: %v", string(bytes))

	return nil
}
