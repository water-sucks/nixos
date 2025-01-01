package cmd

import (
	"encoding/json"
	"fmt"

	"github.com/spf13/cobra"

	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
)

func EnterCommand() *cobra.Command {
	opts := cmdTypes.EnterOpts{}

	cmd := cobra.Command{
		Use:   "enter [flags] [-- ARGS...]",
		Short: "Chroot into a NixOS installation",
		Long:  "Enter a NixOS chroot environment.",
		RunE: func(cmd *cobra.Command, args []string) error {
			if len(args) > 0 {
				opts.CommandArray = args
			}
			return enterMain(cmd, &opts)
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

func enterMain(_ *cobra.Command, opts *cmdTypes.EnterOpts) error {
	if len(opts.CommandArray) > 0 && len(opts.Command) > 1 {
		fmt.Println("warning: preferring --command flag over positional args, both were specified")
	}

	bytes, _ := json.MarshalIndent(opts, "", "  ")
	fmt.Printf("enter: %v\n", string(bytes))

	return nil
}
