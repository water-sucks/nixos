package diff

import (
	"fmt"
	"path/filepath"
	"strconv"

	"github.com/spf13/cobra"

	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
	"github.com/water-sucks/nixos/internal/constants"
	"github.com/water-sucks/nixos/internal/generation"
	"github.com/water-sucks/nixos/internal/logger"
	"github.com/water-sucks/nixos/internal/settings"
	"github.com/water-sucks/nixos/internal/system"
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
		ValidArgsFunction: generation.CompleteGenerationNumber(&genOpts.ProfileName, 2),
		RunE: func(cmd *cobra.Command, args []string) error {
			return cmdUtils.CommandErrorHandler(generationDiffMain(cmd, genOpts, &opts))
		},
	}

	cmd.Flags().BoolVarP(&opts.Verbose, "verbose", "v", false, "Show verbose logging")

	cmd.SetHelpTemplate(cmd.HelpTemplate() + `
Arguments:
  [BEFORE]  Number of first generation to compare with
  [AFTER]   Number of second generation to compare with
`)
	cmdUtils.SetHelpFlagText(&cmd)

	return &cmd
}

func generationDiffMain(cmd *cobra.Command, genOpts *cmdTypes.GenerationOpts, opts *cmdTypes.GenerationDiffOpts) error {
	log := logger.FromContext(cmd.Context())
	cfg := settings.FromContext(cmd.Context())
	s := system.NewLocalSystem()

	profileDirectory := constants.NixProfileDirectory
	if genOpts.ProfileName != "system" {
		profileDirectory = constants.NixSystemProfileDirectory
	}

	beforeDirectory := filepath.Join(profileDirectory, fmt.Sprintf("%v-%v-link", genOpts.ProfileName, opts.Before))
	afterDirectory := filepath.Join(profileDirectory, fmt.Sprintf("%v-%v-link", genOpts.ProfileName, opts.After))

	err := generation.RunDiffCommand(log, s, beforeDirectory, afterDirectory, &generation.DiffCommandOptions{
		UseNvd:  cfg.UseNvd,
		Verbose: opts.Verbose,
	})
	if err != nil {
		log.Errorf("failed to run diff command: %v", err)
		return err
	}

	return nil
}
