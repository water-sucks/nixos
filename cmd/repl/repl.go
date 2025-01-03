package repl

import (
	"encoding/json"
	"fmt"

	"github.com/spf13/cobra"
	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"

	buildOpts "github.com/water-sucks/nixos/internal/build"
)

func ReplCommand() *cobra.Command {
	opts := cmdTypes.ReplOpts{}

	cmd := cobra.Command{
		Use:   "repl [flags] [FLAKE-REF]",
		Short: "Start a Nix REPL with system configuration loaded",
		Long:  "Start a Nix REPL with current system's configuration loaded.",
		Args: func(cmd *cobra.Command, args []string) error {
			if buildOpts.Flake == "true" {
				if err := cobra.MaximumNArgs(1)(cmd, args); err != nil {
					return err
				}
				if len(args) > 0 {
					opts.FlakeRef = args[0]
				}
				return nil
			}
			return cobra.NoArgs(cmd, args)
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			return replMain(cmd, &opts)
		},
	}

	cmdUtils.SetHelpFlagText(&cmd)

	cmd.Flags().StringSliceVarP(&opts.NixPathIncludes, "include", "I", nil, "Add a `path` value to the Nix search path")
	cmd.SetHelpTemplate(cmd.HelpTemplate() + `
Arguments:
    [FLAKE-REF]  Flake ref to load attributes from (default: $NIXOS_CONFIG)
`)

	return &cmd
}

func replMain(_ *cobra.Command, opts *cmdTypes.ReplOpts) error {
	bytes, _ := json.MarshalIndent(opts, "", "  ")
	fmt.Printf("repl: %v\n", string(bytes))
	return nil
}
