package cmd

import (
	"encoding/json"
	"fmt"

	"github.com/spf13/cobra"
	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
)

func FeatureCommand() *cobra.Command {
	opts := cmdTypes.FeaturesOpts{}

	cmd := cobra.Command{
		Use:   "features",
		Short: "Show metadata about this application",
		Long:  "Show metadata about this application and configured options.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return featuresMain(cmd, &opts)
		},
	}

	cmdUtils.SetHelpFlagText(cmd)

	cmd.Flags().BoolVarP(&opts.DisplayJson, "json", "j", false, "Output information in JSON format")

	return &cmd
}

func featuresMain(_ *cobra.Command, opts *cmdTypes.FeaturesOpts) error {
	bytes, _ := json.MarshalIndent(opts, "", "  ")
	fmt.Printf("features: %v\n", string(bytes))
	return nil
}
