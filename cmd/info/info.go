package info

import (
	"encoding/json"

	"github.com/spf13/cobra"
	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
	"github.com/water-sucks/nixos/internal/logger"
)

func InfoCommand() *cobra.Command {
	opts := cmdTypes.InfoOpts{}

	cmd := cobra.Command{
		Use:   "info",
		Short: "Show info about the currently running generation",
		Long:  "Show information about the currently running NixOS generation.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return cmdUtils.CommandErrorHandler(infoMain(cmd, &opts))
		},
	}

	cmdUtils.SetHelpFlagText(&cmd)

	cmd.Flags().BoolVarP(&opts.DisplayJson, "json", "j", false, "Format output as JSON")
	cmd.Flags().BoolVarP(&opts.DisplayMarkdown, "markdown", "m", false, "Format output as Markdown for reporting")

	return &cmd
}

func infoMain(cmd *cobra.Command, opts *cmdTypes.InfoOpts) error {
	log := logger.FromContext(cmd.Context())

	bytes, _ := json.MarshalIndent(opts, "", "  ")
	// Haha, info's gonna be repeated.
	log.Infof("info: %v", string(bytes))

	return nil
}
