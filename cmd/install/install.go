package install

import (
	"encoding/json"
	"fmt"
	"path/filepath"

	"github.com/spf13/cobra"
	buildOpts "github.com/water-sucks/nixos/internal/build"
	nixOpts "github.com/water-sucks/nixos/internal/cmd/nixopts"
	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
)

func InstallCommand() *cobra.Command {
	opts := cmdTypes.InstallOpts{}

	usage := "install"
	if buildOpts.Flake == "true" {
		usage += " {FLAKE-URI}#{SYSTEM-NAME}"
	}

	cmd := cobra.Command{
		Use:   usage,
		Short: "Install a NixOS system",
		Long:  "Install a NixOS system from a given configuration.",
		Args: func(cmd *cobra.Command, args []string) error {
			if buildOpts.Flake == "true" {
				if err := cobra.ExactArgs(1)(cmd, args); err != nil {
					return err
				}
				// TODO: parse flake ref, make sure it is correct
				opts.FlakeRef = args[0]
			} else {
				if err := cobra.NoArgs(cmd, args); err != nil {
					return err
				}
			}
			return nil
		},
		PreRunE: func(cmd *cobra.Command, args []string) error {
			if len(opts.Root) > 0 && !filepath.IsAbs(opts.Root) {
				return fmt.Errorf("--root must be an absolute path")
			}
			if len(opts.SystemClosure) > 0 && !filepath.IsAbs(opts.SystemClosure) {
				return fmt.Errorf("--system must be an absolute path")
			}
			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			return installMain(cmd, &opts)
		},
	}

	cmd.Flags().StringVarP(&opts.Channel, "channel", "c", "", "Use derivation at `path` as the 'nixos' channel to copy")
	cmd.Flags().BoolVar(&opts.NoBootloader, "no-bootloader", false, "Do not install bootloader on device")
	cmd.Flags().BoolVar(&opts.NoChannelCopy, "no-channel-copy", false, "Do not copy over a NixOS channel")
	cmd.Flags().BoolVar(&opts.NoRootPassword, "no-root-passwd", false, "Do not prompt for setting root password")
	cmd.Flags().StringVarP(&opts.Root, "root", "r", "/mnt", "Treat `dir` as the root for installation")
	cmd.Flags().StringVarP(&opts.SystemClosure, "system", "s", "", "Install system from system closure at `path`")
	cmd.Flags().BoolVarP(&opts.Verbose, "verbose", "v", false, "Show verbose logging")

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

	cmd.MarkFlagsMutuallyExclusive("channel", "no-channel-copy")

	helpTemplate := cmd.HelpTemplate()
	if buildOpts.Flake == "true" {
		helpTemplate += `
Arguments:
  [FLAKE-URI]    Flake URI that contains NixOS system to build
  [SYSTEM-NAME]  Name of NixOS system attribute to build
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

func installMain(_ *cobra.Command, opts *cmdTypes.InstallOpts) error {
	bytes, _ := json.MarshalIndent(opts, "", "  ")
	fmt.Printf("install: %v\n", string(bytes))
	return nil
}
