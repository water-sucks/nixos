package cmd

import (
	"encoding/json"
	"fmt"

	"github.com/spf13/cobra"

	cmdUtils "github.com/water-sucks/nixos/internal/cmd"
)

type aliasesOpts struct {
	DisplayJson bool
}

func AliasCommand() *cobra.Command {
	opts := aliasesOpts{}

	cmd := cobra.Command{
		Use:   "aliases",
		Short: "List configured aliases",
		Long:  "List configured aliases and what commands they resolve to.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return aliasesMain(cmd, &opts)
		},
	}

	cmd.Flags().BoolVarP(&opts.DisplayJson, "json", "j", false, "Output information in JSON format")

	cmdUtils.SetHelpFlagText(cmd)

	return &cmd
}

func aliasesMain(_ *cobra.Command, opts *aliasesOpts) error {
	bytes, _ := json.MarshalIndent(opts, "", "  ")
	fmt.Printf("aliases: %v\n", string(bytes))
	return nil
}
