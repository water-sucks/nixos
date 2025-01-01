package cmd

import (
	"encoding/json"
	"fmt"

	"github.com/spf13/cobra"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd"
)

type featuresOpts struct {
	DisplayJson bool
}

func FeatureCommand() *cobra.Command {
	opts := featuresOpts{}

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

func featuresMain(_ *cobra.Command, opts *featuresOpts) error {
	bytes, _ := json.MarshalIndent(opts, "", "  ")
	fmt.Printf("features: %v\n", string(bytes))
	return nil
}
