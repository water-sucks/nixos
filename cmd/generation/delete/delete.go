package delete

import (
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/spf13/cobra"

	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
)

func GenerationDeleteCommand(genOpts *cmdTypes.GenerationOpts) *cobra.Command {
	opts := cmdTypes.GenerationDeleteOpts{}

	cmd := cobra.Command{
		Use:   "delete [flags] [GEN...]",
		Short: "Delete generations from this system",
		Long:  "Delete NixOS generations from this system.",
		Args: func(cmd *cobra.Command, args []string) error {
			for _, v := range args {
				value, err := strconv.ParseInt(v, 10, 32)
				if err != nil {
					return fmt.Errorf("[GEN] must be integer value, got '%v'", v)
				}
				opts.Delete = append(opts.Delete, uint(value))
			}
			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			return generationDeleteMain(cmd, genOpts, &opts)
		},
	}

	cmd.Flags().BoolVarP(&opts.All, "all", "a", false, "Delete all generations except the current one")
	cmd.Flags().UintVarP(&opts.LowerBound, "from", "f", 0, "Delete all generations after `gen`, inclusive")
	cmd.Flags().UintVarP(&opts.UpperBound, "to", "t", 0, "Delete all generations until `gen`, inclusive")
	cmd.Flags().UintVarP(&opts.MinimumToKeep, "min", "m", 0, "Keep a minimum of `num` generations")
	cmd.Flags().StringVarP(&opts.OlderThan, "older-than", "o", "", "Delete all generations older than `period`")
	cmd.Flags().UintSliceVarP(&opts.Keep, "keep", "k", nil, "Always keep this `gen`, can be specified many times")
	cmd.Flags().BoolVarP(&opts.AlwaysConfirm, "yes", "y", false, "Automatically confirm generation deletion")

	cmdUtils.SetHelpFlagText(&cmd)
	cmd.SetHelpTemplate(cmd.HelpTemplate() + `
Arguments:
    [GEN]       Generation number

These options and arguments can be combined ad-hoc as constraints.

The 'period' parameter in --older-than is a systemd.time(7) span
(i.e. "30d 2h 1m"). Check the manual page for more information.
`)

	return &cmd
}

func generationDeleteMain(_ *cobra.Command, genOpts *cmdTypes.GenerationOpts, opts *cmdTypes.GenerationDeleteOpts) error {
	bytes, _ := json.MarshalIndent(opts, "", "  ")
	bytes2, _ := json.MarshalIndent(genOpts, "", "  ")

	fmt.Printf("generation delete: %v, %v\n", string(bytes2), string(bytes))
	return nil
}
