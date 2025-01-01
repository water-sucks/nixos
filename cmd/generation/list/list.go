package list

import (
	"encoding/json"
	"fmt"

	"github.com/spf13/cobra"

	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
)

func GenerationListCommand(genOpts *cmdTypes.GenerationOpts) *cobra.Command {
	opts := cmdTypes.GenerationListOpts{}

	cmd := cobra.Command{
		Use:   "list",
		Short: "List all NixOS generations in a profile",
		Long:  "List all generations in a NixOS profile and their details.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return generationListMain(cmd, genOpts, &opts)
		},
	}

	cmd.Flags().BoolVarP(&opts.Interactive, "interactive", "i", false, "Show a TUI to look through generations")
	cmd.Flags().BoolVarP(&opts.DisplayJson, "json", "j", false, "Display format as JSON")

	cmdUtils.SetHelpFlagText(&cmd)

	return &cmd
}

func generationListMain(_ *cobra.Command, genOpts *cmdTypes.GenerationOpts, opts *cmdTypes.GenerationListOpts) error {
	bytes, _ := json.MarshalIndent(opts, "", "  ")
	bytes2, _ := json.MarshalIndent(genOpts, "", "  ")

	fmt.Printf("generation list: %v, %v\n", string(bytes2), string(bytes))
	return nil
}
