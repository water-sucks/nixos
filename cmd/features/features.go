package cmd

import (
	"encoding/json"
	"fmt"
	"runtime"

	"github.com/spf13/cobra"
	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"

	buildOpts "github.com/water-sucks/nixos/internal/build"
)

func FeatureCommand() *cobra.Command {
	opts := cmdTypes.FeaturesOpts{}

	cmd := cobra.Command{
		Use:   "features",
		Short: "Show metadata about this application",
		Long:  "Show metadata about this application and configured options.",
		Run: func(cmd *cobra.Command, args []string) {
			featuresMain(cmd, &opts)
		},
	}

	cmdUtils.SetHelpFlagText(&cmd)

	cmd.Flags().BoolVarP(&opts.DisplayJson, "json", "j", false, "Output information in JSON format")

	return &cmd
}

type features struct {
	Version            string              `json:"version"`
	GitRevision        string              `json:"git_rev"`
	GoVersion          string              `json:"go_version"`
	CompilationOptions complilationOptions `json:"options"`
}

type complilationOptions struct {
	NixpkgsVersion string `json:"nixpkgs_version"`
	Flake          bool   `json:"flake"`
}

func featuresMain(_ *cobra.Command, opts *cmdTypes.FeaturesOpts) {
	features := features{
		Version:     buildOpts.Version,
		GitRevision: buildOpts.GitRevision,
		GoVersion:   runtime.Version(),
		CompilationOptions: complilationOptions{
			NixpkgsVersion: buildOpts.NixpkgsVersion,
			Flake:          buildOpts.Flake == "true",
		},
	}

	if opts.DisplayJson {
		bytes, _ := json.MarshalIndent(features, "", "  ")
		fmt.Printf("%v\n", string(bytes))

		return
	}

	fmt.Printf("nixos %v\n", features.Version)
	fmt.Printf("git rev: %v\n", features.GitRevision)
	fmt.Printf("go version: %v\n\n", features.GoVersion)

	fmt.Println("Compilation Options")
	fmt.Println("-------------------")

	fmt.Printf("flake           :: %v\n", features.CompilationOptions.Flake)
	fmt.Printf("nixpkgs_version :: %v\n", features.CompilationOptions.NixpkgsVersion)
}
