package info

import (
	"encoding/json"
	"fmt"

	"github.com/spf13/cobra"
	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
)

func InfoCommand() *cobra.Command {
	opts := cmdTypes.InfoOpts{}

	cmd := cobra.Command{
		Use:   "info",
		Short: "Show info about the currently running generation",
		Long:  "Show information about the currently running NixOS generation.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return infoMain(cmd, &opts)
		},
	}

	cmdUtils.SetHelpFlagText(&cmd)

	cmd.Flags().BoolVarP(&opts.DisplayJson, "json", "j", false, "Format output as JSON")
	cmd.Flags().BoolVarP(&opts.DisplayMarkdown, "markdown", "m", false, "Format output as Markdown for reporting")

	return &cmd
}

func infoMain(_ *cobra.Command, opts *cmdTypes.InfoOpts) error {
	bytes, _ := json.MarshalIndent(opts, "", "  ")
	fmt.Printf("info: %v\n", string(bytes))
	return nil
}
