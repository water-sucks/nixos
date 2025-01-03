package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
)

func ManualCommand() *cobra.Command {
	cmd := cobra.Command{
		Use:   "manual",
		Short: "Open the NixOS manual",
		Long:  "Open the NixOS manual in a browser.",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return manualMain(cmd)
		},
	}

	cmdUtils.SetHelpFlagText(&cmd)

	return &cmd
}

func manualMain(_ *cobra.Command) error {
	fmt.Println("manual")
	return nil
}
