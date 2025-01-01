package cmd

import (
	"encoding/json"
	"fmt"

	"github.com/spf13/cobra"

	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
)

func AliasCommand() *cobra.Command {
	opts := cmdTypes.AliasesOpts{}

	cmd := cobra.Command{
		Use:   "aliases",
		Short: "List configured aliases",
		Long:  "List configured aliases and what commands they resolve to.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return aliasesMain(cmd, &opts)
		},
	}

	cmd.Flags().BoolVarP(&opts.DisplayJson, "json", "j", false, "Output information in JSON format")

	cmdUtils.SetHelpFlagText(&cmd)

	return &cmd
}

func aliasesMain(_ *cobra.Command, opts *cmdTypes.AliasesOpts) error {
	bytes, _ := json.MarshalIndent(opts, "", "  ")
	fmt.Printf("aliases: %v\n", string(bytes))
	return nil
}
