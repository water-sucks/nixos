package cmd

import (
	"github.com/spf13/cobra"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
	"github.com/water-sucks/nixos/internal/logger"
)

func ManualCommand() *cobra.Command {
	cmd := cobra.Command{
		Use:   "manual",
		Short: "Open the NixOS manual",
		Long:  "Open the NixOS manual in a browser.",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return cmdUtils.CommandErrorHandler(manualMain(cmd))
		},
	}

	cmdUtils.SetHelpFlagText(&cmd)

	return &cmd
}

func manualMain(cmd *cobra.Command) error {
	log := logger.FromContext(cmd.Context())

	log.Info("manual")
	return nil
}
