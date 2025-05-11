package generation

import (
	"github.com/spf13/cobra"

	"github.com/water-sucks/nixos/internal/cmd/opts"
	"github.com/water-sucks/nixos/internal/cmd/utils"
	"github.com/water-sucks/nixos/internal/generation"

	genDeleteCmd "github.com/water-sucks/nixos/cmd/generation/delete"
	genDiffCmd "github.com/water-sucks/nixos/cmd/generation/diff"
	genListCmd "github.com/water-sucks/nixos/cmd/generation/list"
	genRollbackCmd "github.com/water-sucks/nixos/cmd/generation/rollback"
	genSwitchCmd "github.com/water-sucks/nixos/cmd/generation/switch"
)

func GenerationCommand() *cobra.Command {
	opts := cmdOpts.GenerationOpts{}

	cmd := cobra.Command{
		Use:   "generation {command}",
		Short: "Manage NixOS generations",
		Long:  "Manage NixOS generations on this machine.",
	}

	cmd.PersistentFlags().StringVarP(&opts.ProfileName, "profile", "p", "system", "System profile to use")

	cmd.AddCommand(genDeleteCmd.GenerationDeleteCommand(&opts))
	cmd.AddCommand(genDiffCmd.GenerationDiffCommand(&opts))
	cmd.AddCommand(genListCmd.GenerationListCommand(&opts))
	cmd.AddCommand(genSwitchCmd.GenerationSwitchCommand(&opts))
	cmd.AddCommand(genRollbackCmd.GenerationRollbackCommand(&opts))

	cmdUtils.SetHelpFlagText(&cmd)

	_ = cmd.RegisterFlagCompletionFunc("profile", generation.CompleteProfileFlag)

	return &cmd
}
