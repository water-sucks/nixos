package switch_cmd

import (
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/spf13/cobra"

	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
	"github.com/water-sucks/nixos/internal/logger"
)

func GenerationSwitchCommand(genOpts *cmdTypes.GenerationOpts) *cobra.Command {
	opts := cmdTypes.GenerationSwitchOpts{}

	cmd := cobra.Command{
		Use:   "switch [flags] {GEN}",
		Short: "Activate an existing generation",
		Long:  "Activate an arbitrary existing NixOS generation",
		Args: func(cmd *cobra.Command, args []string) error {
			if err := cobra.ExactArgs(1)(cmd, args); err != nil {
				return err
			}

			arg := args[0]
			gen, err := strconv.ParseInt(arg, 10, 32)
			if err != nil {
				return fmt.Errorf("{GEN} must be integer value, got '%v'", arg)
			}
			opts.Generation = uint(gen)

			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			return cmdUtils.CommandErrorHandler(generationSwitchMain(cmd, genOpts, &opts))
		},
	}

	cmd.Flags().BoolVarP(&opts.Dry, "dry", "d", false, "Show what would be activated, but do not activate")
	cmd.Flags().StringVarP(&opts.Specialisation, "specialisation", "s", "", "Activate the specialisation with `name`")
	cmd.Flags().BoolVarP(&opts.Verbose, "verbose", "v", false, "Show verbose logging")
	cmd.Flags().BoolVarP(&opts.AlwaysConfirm, "yes", "y", false, "Automatically confirm activation")

	cmdUtils.SetHelpFlagText(&cmd)
	cmd.SetHelpTemplate(cmd.HelpTemplate() + `
Arguments:
    [GEN]       Generation number
`)

	return &cmd
}

func generationSwitchMain(cmd *cobra.Command, genOpts *cmdTypes.GenerationOpts, opts *cmdTypes.GenerationSwitchOpts) error {
	log := logger.FromContext(cmd.Context())

	bytes, _ := json.MarshalIndent(opts, "", "  ")
	bytes2, _ := json.MarshalIndent(genOpts, "", "  ")

	log.Infof("generation switch: %v, %v", string(bytes2), string(bytes))
	return nil
}
