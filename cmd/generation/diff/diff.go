package diff

import (
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/spf13/cobra"

	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
)

func GenerationDiffCommand(genOpts *cmdTypes.GenerationOpts) *cobra.Command {
	opts := cmdTypes.GenerationDiffOpts{}

	cmd := cobra.Command{
		Use:   "diff {BEFORE} {AFTER}",
		Short: "Show what changed between two generations",
		Long:  "Display what paths differ between two generations.",
		Args: func(cmd *cobra.Command, args []string) error {
			if err := cobra.ExactArgs(2)(cmd, args); err != nil {
				return err
			}

			before, err := strconv.ParseInt(args[0], 10, 32)
			if err != nil {
				return fmt.Errorf("{BEFORE} must be an integer, got '%v'", before)
			}
			opts.Before = uint(before)

			after, err := strconv.ParseInt(args[1], 10, 32)
			if err != nil {
				return fmt.Errorf("{AFTER} must be an integer, got '%v'", after)
			}
			opts.After = uint(after)

			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			return generationDiffMain(cmd, genOpts, &opts)
		},
	}

	cmd.SetHelpTemplate(cmd.HelpTemplate() + `
Arguments:
  [BEFORE]  Number of first generation to compare with
  [AFTER]   Number of second generation to compare with
`)
	cmdUtils.SetHelpFlagText(&cmd)

	return &cmd
}

func generationDiffMain(_ *cobra.Command, genOpts *cmdTypes.GenerationOpts, opts *cmdTypes.GenerationDiffOpts) error {
	bytes, _ := json.MarshalIndent(opts, "", "  ")
	bytes2, _ := json.MarshalIndent(genOpts, "", "  ")

	fmt.Printf("generation diff: %v, %v\n", string(bytes2), string(bytes))
	return nil
}
