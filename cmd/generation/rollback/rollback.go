package rollback

import (
	"encoding/json"

	"github.com/spf13/cobra"

	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
	"github.com/water-sucks/nixos/internal/logger"
)

func GenerationRollbackCommand(genOpts *cmdTypes.GenerationOpts) *cobra.Command {
	opts := cmdTypes.GenerationRollbackOpts{}

	cmd := cobra.Command{
		Use:   "rollback [flags] {GEN}",
		Short: "Activate the previous generation",
		Long:  "Rollback to the previous NixOS generation.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return cmdUtils.CommandErrorHandler(generationRollbackMain(cmd, genOpts, &opts))
		},
	}

	cmd.Flags().BoolVarP(&opts.Dry, "dry", "d", false, "Show what would be activated, but do not activate")
	cmd.Flags().StringVarP(&opts.Specialisation, "specialisation", "s", "", "Activate the specialisation with `name`")
	cmd.Flags().BoolVarP(&opts.Verbose, "verbose", "v", false, "Show verbose logging")
	cmd.Flags().BoolVarP(&opts.AlwaysConfirm, "yes", "y", false, "Automatically confirm activation")

	cmdUtils.SetHelpFlagText(&cmd)

	return &cmd
}

func generationRollbackMain(cmd *cobra.Command, genOpts *cmdTypes.GenerationOpts, opts *cmdTypes.GenerationRollbackOpts) error {
	log := logger.FromContext(cmd.Context())

	bytes, _ := json.MarshalIndent(opts, "", "  ")
	bytes2, _ := json.MarshalIndent(genOpts, "", "  ")

	log.Infof("generation rollback: %v, %v", string(bytes2), string(bytes))
	return nil
}
