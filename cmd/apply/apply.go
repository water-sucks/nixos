package cmd

import (
	"encoding/json"
	"fmt"

	"github.com/spf13/cobra"
	buildOpts "github.com/water-sucks/nixos/internal/build"
	nixOpts "github.com/water-sucks/nixos/internal/cmd/nixopts"
	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
	"github.com/water-sucks/nixos/internal/logger"
)

func ApplyCommand() *cobra.Command {
	opts := cmdTypes.ApplyOpts{}

	usage := "apply"
	if buildOpts.Flake == "true" {
		usage += " [FLAKE-REF]"
	}

	cmd := cobra.Command{
		Use:   usage,
		Short: "Build/activate a NixOS configuration",
		Long:  "Build and activate a NixOS system from a given configuration.",
		Args: func(cmd *cobra.Command, args []string) error {
			if buildOpts.Flake == "true" {
				if err := cobra.MaximumNArgs(1)(cmd, args); err != nil {
					return err
				}
				if len(args) > 0 {
					opts.FlakeRef = args[0]
				}
			} else {
				if err := cobra.NoArgs(cmd, args); err != nil {
					return err
				}
			}
			return nil
		},
		PreRunE: func(cmd *cobra.Command, args []string) error {
			if opts.NoActivate && opts.NoBoot && opts.InstallBootloader {
				return fmt.Errorf("--install-bootloader requires activation, remove --no-activate and/or --no-boot to use this option")
			}
			if buildOpts.Flake == "true" && opts.GenerationTag != "" && !opts.NixOptions.Impure {
				return fmt.Errorf("--impure is required when using --tag for flake configurations")
			}
			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			return applyMain(cmd, &opts)
		},
	}

	cmd.Flags().BoolVarP(&opts.Dry, "dry", "d", false, "Show what would be built or ran")
	cmd.Flags().BoolVar(&opts.InstallBootloader, "install-bootloader", false, "(Re)install the bootloader on the configured device(s)")
	cmd.Flags().BoolVar(&opts.NoActivate, "no-activate", false, "Do not activate the built configuration")
	cmd.Flags().BoolVar(&opts.NoBoot, "no-boot", false, "Do not create boot entry for this generation")
	cmd.Flags().StringVarP(&opts.OutputPath, "output", "o", "", "Symlink the output to `location`")
	cmd.Flags().StringVarP(&opts.ProfileName, "profile-name", "p", "", "Store generations using the profile `name`")
	cmd.Flags().StringVarP(&opts.Specialisation, "specialisation", "s", "", "Activate the specialisation with `name`")
	cmd.Flags().StringVarP(&opts.GenerationTag, "tag", "t", "", "Tag this generation with a `description`")
	cmd.Flags().BoolSliceVarP(&opts.Verbosity, "verbose", "v", opts.Verbosity, "Show verbose logging")
	cmd.Flags().BoolVar(&opts.BuildVM, "vm", false, "Build a NixOS VM script")
	cmd.Flags().BoolVar(&opts.BuildVMWithBootloader, "vm-with-bootloader", false, "Build a NixOS VM script with a bootloader")
	cmd.Flags().BoolVarP(&opts.AlwaysConfirm, "yes", "y", false, "Automatically confirm activation")

	nixOpts.AddQuietNixOption(&cmd, &opts.NixOptions.Quiet)
	nixOpts.AddPrintBuildLogsNixOption(&cmd, &opts.NixOptions.PrintBuildLogs)
	nixOpts.AddNoBuildOutputNixOption(&cmd, &opts.NixOptions.NoBuildOutput)
	nixOpts.AddShowTraceNixOption(&cmd, &opts.NixOptions.ShowTrace)
	nixOpts.AddKeepGoingNixOption(&cmd, &opts.NixOptions.KeepGoing)
	nixOpts.AddKeepFailedNixOption(&cmd, &opts.NixOptions.KeepFailed)
	nixOpts.AddFallbackNixOption(&cmd, &opts.NixOptions.Fallback)
	nixOpts.AddRefreshNixOption(&cmd, &opts.NixOptions.Refresh)
	nixOpts.AddRepairNixOption(&cmd, &opts.NixOptions.Repair)
	nixOpts.AddImpureNixOption(&cmd, &opts.NixOptions.Impure)
	nixOpts.AddOfflineNixOption(&cmd, &opts.NixOptions.Offline)
	nixOpts.AddNoNetNixOption(&cmd, &opts.NixOptions.NoNet)
	nixOpts.AddMaxJobsNixOption(&cmd, &opts.NixOptions.MaxJobs)
	nixOpts.AddCoresNixOption(&cmd, &opts.NixOptions.Cores)
	nixOpts.AddBuildersNixOption(&cmd, &opts.NixOptions.Builders)
	nixOpts.AddLogFormatNixOption(&cmd, &opts.NixOptions.LogFormat)
	nixOpts.AddOptionNixOption(&cmd, &opts.NixOptions.Options)

	if buildOpts.Flake == "true" {
		nixOpts.AddRecreateLockFileNixOption(&cmd, &opts.NixOptions.RecreateLockFile)
		nixOpts.AddNoUpdateLockFileNixOption(&cmd, &opts.NixOptions.NoUpdateLockFile)
		nixOpts.AddNoWriteLockFileNixOption(&cmd, &opts.NixOptions.NoWriteLockFile)
		nixOpts.AddNoUseRegistriesNixOption(&cmd, &opts.NixOptions.NoUseRegistries)
		nixOpts.AddCommitLockFileNixOption(&cmd, &opts.NixOptions.CommitLockFile)
		nixOpts.AddUpdateInputNixOption(&cmd, &opts.NixOptions.UpdateInputs)
		nixOpts.AddOverrideInputNixOption(&cmd, &opts.NixOptions.OverrideInputs)
	}

	cmd.MarkFlagsMutuallyExclusive("dry", "output")
	cmd.MarkFlagsMutuallyExclusive("vm", "vm-with-bootloader")
	cmd.MarkFlagsMutuallyExclusive("no-activate", "specialisation")

	helpTemplate := cmd.HelpTemplate()
	if buildOpts.Flake == "true" {
		helpTemplate += `
Arguments:
  [FLAKE-REF]  Flake ref to build configuration from (default: $NIXOS_CONFIG)
`
	}
	helpTemplate += `
This command also forwards Nix options passed here to all relevant Nix invocations.
Check the Nix manual page for more details on what options are available.
`

	cmdUtils.SetHelpFlagText(&cmd)
	cmd.SetHelpTemplate(helpTemplate)

	return &cmd
}

func applyMain(cmd *cobra.Command, opts *cmdTypes.ApplyOpts) error {
	log := logger.FromContext(cmd.Context())

	bytes, _ := json.MarshalIndent(opts, "", "  ")
	log.Infof("apply: %v", string(bytes))

	return nil
}
