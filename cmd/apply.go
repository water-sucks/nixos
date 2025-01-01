package cmd

import (
	"encoding/json"
	"fmt"

	"github.com/spf13/cobra"
	buildOpts "github.com/water-sucks/nixos/internal/build"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd"
)

type applyOpts struct {
	Dry                   bool
	InstallBootloader     bool
	NoActivate            bool
	NoBoot                bool
	OutputPath            string
	ProfileName           string
	Specialisation        string
	GenerationTag         string
	UseNom                bool
	Verbosity             []bool
	BuildVM               bool
	BuildVMWithBootloader bool
	AlwaysConfirm         bool
	FlakeRef              string

	NixOptions struct {
		Quiet          bool
		PrintBuildLogs bool
		NoBuildOutput  bool
		ShowTrace      bool
		KeepGoing      bool
		KeepFailed     bool
		Fallback       bool
		Refresh        bool
		Repair         bool
		Impure         bool
		Offline        bool
		NoNet          bool
		MaxJobs        int
		Cores          int
		Builders       []string
		LogFormat      string
		Options        map[string]string

		RecreateLockFile bool
		NoUpdateLockFile bool
		NoWriteLockFile  bool
		NoUseRegistries  bool
		CommitLockFile   bool
		UpdateInputs     []string
		OverrideInputs   map[string]string
	}
}

func applyCmd() *cobra.Command {
	opts := applyOpts{}

	cmd := cobra.Command{
		Use:   "apply [FLAKE-REF]",
		Short: "Build/activate a NixOS configuration",
		Long:  "Build and activate a NixOS system from a given configuration.",
		Args: func(cmd *cobra.Command, args []string) error {
			if buildOpts.Flake == "true" {
				if err := cobra.MaximumNArgs(1)(cmd, args); err != nil {
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
			if len(args) > 0 && buildOpts.Flake == "true" {
				opts.FlakeRef = args[0]
			}
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

	cmdUtils.AddQuietNixOption(&cmd, &opts.NixOptions.Quiet)
	cmdUtils.AddPrintBuildLogsNixOption(&cmd, &opts.NixOptions.PrintBuildLogs)
	cmdUtils.AddNoBuildOutputNixOption(&cmd, &opts.NixOptions.NoBuildOutput)
	cmdUtils.AddShowTraceNixOption(&cmd, &opts.NixOptions.ShowTrace)
	cmdUtils.AddKeepGoingNixOption(&cmd, &opts.NixOptions.KeepGoing)
	cmdUtils.AddKeepFailedNixOption(&cmd, &opts.NixOptions.KeepFailed)
	cmdUtils.AddFallbackNixOption(&cmd, &opts.NixOptions.Fallback)
	cmdUtils.AddRefreshNixOption(&cmd, &opts.NixOptions.Refresh)
	cmdUtils.AddRepairNixOption(&cmd, &opts.NixOptions.Repair)
	cmdUtils.AddImpureNixOption(&cmd, &opts.NixOptions.Impure)
	cmdUtils.AddOfflineNixOption(&cmd, &opts.NixOptions.Offline)
	cmdUtils.AddNoNetNixOption(&cmd, &opts.NixOptions.NoNet)
	cmdUtils.AddMaxJobsNixOption(&cmd, &opts.NixOptions.MaxJobs)
	cmdUtils.AddCoresNixOption(&cmd, &opts.NixOptions.Cores)
	cmdUtils.AddBuildersNixOption(&cmd, &opts.NixOptions.Builders)
	cmdUtils.AddLogFormatNixOption(&cmd, &opts.NixOptions.LogFormat)
	cmdUtils.AddOptionNixOption(&cmd, &opts.NixOptions.Options)

	if buildOpts.Flake == "true" {
		cmdUtils.AddRecreateLockFileNixOption(&cmd, &opts.NixOptions.RecreateLockFile)
		cmdUtils.AddNoUpdateLockFileNixOption(&cmd, &opts.NixOptions.NoUpdateLockFile)
		cmdUtils.AddNoWriteLockFileNixOption(&cmd, &opts.NixOptions.NoWriteLockFile)
		cmdUtils.AddNoUseRegistriesNixOption(&cmd, &opts.NixOptions.NoUseRegistries)
		cmdUtils.AddCommitLockFileNixOption(&cmd, &opts.NixOptions.CommitLockFile)
		cmdUtils.AddUpdateInputNixOption(&cmd, &opts.NixOptions.UpdateInputs)
		cmdUtils.AddOverrideInputNixOption(&cmd, &opts.NixOptions.OverrideInputs)
	}

	cmd.MarkFlagsMutuallyExclusive("dry", "output")
	cmd.MarkFlagsMutuallyExclusive("vm", "vm-with-bootloader")
	cmd.MarkFlagsMutuallyExclusive("no-activate", "specialisation")

	cmdUtils.SetHelpFlagText(cmd)
	cmd.SetHelpTemplate(cmd.HelpTemplate() + `
Arguments:
  [FLAKE-REF]  Flake ref to build configuration from (default: $NIXOS_CONFIG)

This command also forwards Nix options passed here to all relevant Nix invocations.
Check the Nix manual page for more details on what options are available.
`)

	return &cmd
}

func applyMain(_ *cobra.Command, opts *applyOpts) error {
	bytes, _ := json.MarshalIndent(opts, "", "  ")
	fmt.Printf("apply: %v\n", string(bytes))
	return nil
}
