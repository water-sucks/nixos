package apply

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/spf13/cobra"
	buildOpts "github.com/water-sucks/nixos/internal/build"
	"github.com/water-sucks/nixos/internal/cmd/nixopts"
	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
	"github.com/water-sucks/nixos/internal/config"
	"github.com/water-sucks/nixos/internal/configuration"
	"github.com/water-sucks/nixos/internal/constants"
	"github.com/water-sucks/nixos/internal/generation"
	"github.com/water-sucks/nixos/internal/logger"
	"github.com/water-sucks/nixos/internal/system"
	"github.com/water-sucks/nixos/internal/utils"
)

func ApplyCommand(cfg *config.Config) *cobra.Command {
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
				if cfg.Apply.ImplyImpureWithTag {
					opts.NixOptions.Impure = true
				} else {
					return fmt.Errorf("--impure is required when using --tag for flake configurations")
				}
			}
			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			return cmdUtils.CommandErrorHandler(applyMain(cmd, &opts))
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
	cmd.Flags().BoolVar(&opts.UseNom, "use-nom", false, "Tag this generation with a `description`")
	cmd.Flags().BoolVarP(&opts.Verbose, "verbose", "v", opts.Verbose, "Show verbose logging")
	cmd.Flags().BoolVar(&opts.BuildVM, "vm", false, "Build a NixOS VM script")
	cmd.Flags().BoolVar(&opts.BuildVMWithBootloader, "vm-with-bootloader", false, "Build a NixOS VM script with a bootloader")
	cmd.Flags().BoolVarP(&opts.AlwaysConfirm, "yes", "y", false, "Automatically confirm activation")

	nixopts.AddQuietNixOption(&cmd, &opts.NixOptions.Quiet)
	nixopts.AddPrintBuildLogsNixOption(&cmd, &opts.NixOptions.PrintBuildLogs)
	nixopts.AddNoBuildOutputNixOption(&cmd, &opts.NixOptions.NoBuildOutput)
	nixopts.AddShowTraceNixOption(&cmd, &opts.NixOptions.ShowTrace)
	nixopts.AddKeepGoingNixOption(&cmd, &opts.NixOptions.KeepGoing)
	nixopts.AddKeepFailedNixOption(&cmd, &opts.NixOptions.KeepFailed)
	nixopts.AddFallbackNixOption(&cmd, &opts.NixOptions.Fallback)
	nixopts.AddRefreshNixOption(&cmd, &opts.NixOptions.Refresh)
	nixopts.AddRepairNixOption(&cmd, &opts.NixOptions.Repair)
	nixopts.AddImpureNixOption(&cmd, &opts.NixOptions.Impure)
	nixopts.AddOfflineNixOption(&cmd, &opts.NixOptions.Offline)
	nixopts.AddNoNetNixOption(&cmd, &opts.NixOptions.NoNet)
	nixopts.AddMaxJobsNixOption(&cmd, &opts.NixOptions.MaxJobs)
	nixopts.AddCoresNixOption(&cmd, &opts.NixOptions.Cores)
	nixopts.AddBuildersNixOption(&cmd, &opts.NixOptions.Builders)
	nixopts.AddLogFormatNixOption(&cmd, &opts.NixOptions.LogFormat)
	nixopts.AddOptionNixOption(&cmd, &opts.NixOptions.Options)

	if buildOpts.Flake == "true" {
		nixopts.AddRecreateLockFileNixOption(&cmd, &opts.NixOptions.RecreateLockFile)
		nixopts.AddNoUpdateLockFileNixOption(&cmd, &opts.NixOptions.NoUpdateLockFile)
		nixopts.AddNoWriteLockFileNixOption(&cmd, &opts.NixOptions.NoWriteLockFile)
		nixopts.AddNoUseRegistriesNixOption(&cmd, &opts.NixOptions.NoUseRegistries)
		nixopts.AddCommitLockFileNixOption(&cmd, &opts.NixOptions.CommitLockFile)
		nixopts.AddUpdateInputNixOption(&cmd, &opts.NixOptions.UpdateInputs)
		nixopts.AddOverrideInputNixOption(&cmd, &opts.NixOptions.OverrideInputs)
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
	cfg := config.FromContext(cmd.Context())
	s := system.NewLocalSystem()

	if !s.IsNixOS() {
		msg := "this command only is only supported on NixOS systems"
		log.Errorf(msg)
		return fmt.Errorf("%v", msg)
	}

	buildType := buildTypeSystemActivation
	if opts.BuildVM {
		buildType = buildTypeVM
	} else if opts.BuildVMWithBootloader {
		buildType = buildTypeVMWithBootloader
	} else if opts.NoActivate && opts.NoBoot {
		buildType = buildTypeSystem
	}
	_ = buildType

	if os.Geteuid() != 0 {
		err := utils.ExecAsRoot(cfg.RootCommand)
		if err != nil {
			log.Errorf("failed to re-exec command as root: %v", err)
			return err
		}
	}

	if opts.Verbose {
		log.Step("Looking for configuration...")
	}

	var flakeRef *configuration.FlakeRef
	var configDirname string

	if buildOpts.Flake == "true" {
		if opts.Verbose {
			log.Info("looking for flake configuration")
		}

		if opts.FlakeRef != "" {
			flakeRef = configuration.FlakeRefFromString(opts.FlakeRef)
		} else {
			f, err := configuration.FlakeRefFromEnv(cfg.ConfigLocation)
			if err != nil {
				log.Errorf("failed to find flake configuration: %v", err)
				return err
			}
			flakeRef = f
		}

		if err := flakeRef.InferSystemFromHostnameIfNeeded(); err != nil {
			log.Errorf("failed to infer system name from hostname: %v", err)
			return err
		}

		if opts.Verbose {
			log.Infof("found flake configuration: %s#%s", flakeRef.URI, flakeRef.System)
		}
	} else {
		c, err := configuration.FindLegacyConfiguration(log, opts.Verbose)
		if err != nil {
			log.Errorf("failed to find configuration: %v", err)
			return err
		}
		configDirname = c
	}

	if configDirname != "" {
		// Change to the configuration directory, if it exists:
		// this will likely fail for remote configurations or
		// configurations accessed through the registry, which
		// should be a rare occurrence, but valid, so ignore any
		// errors in that case.
		_ = os.Chdir(configDirname)
	}

	if buildType.IsVM() {
		log.Step("Building VM...")
	} else {
		log.Step("Building configuration...")
	}

	useNom := cfg.Apply.UseNom || opts.UseNom
	nomPath, _ := exec.LookPath("nom")
	nomFound := nomPath != ""
	if opts.UseNom && !nomFound {
		log.Error("--use-nom was specified, but `nom` is not executable")
	} else if cfg.Apply.UseNom && !nomFound {
		log.Warn("apply.use_nom is specified in config, but `nom` is not executable")
		log.Warn("falling back to `nix` command for building")
		useNom = false
	}

	// Dry activation requires a real build, so --dry-run shouldn't be set
	// if --activate or --boot is set
	dryBuild := opts.Dry && buildType == buildTypeSystem

	buildOptions := &buildOptions{
		NixOpts:        &opts.NixOptions,
		ResultLocation: opts.OutputPath,
		DryBuild:       dryBuild,
		UseNom:         useNom,
		GenerationTag:  opts.GenerationTag,
		Verbose:        opts.Verbose,
	}

	var resultLocation string
	if buildOpts.Flake == "true" {
		buildOutput, err := buildFlake(s, log, flakeRef, buildType, buildOptions)
		if err != nil {
			log.Errorf("failed to build configuration: %v", err)
			return err
		}
		resultLocation = buildOutput
	} else {
		buildOutput, err := buildLegacy(s, log, buildType, buildOptions)
		if err != nil {
			log.Errorf("failed to build configuration: %v", err)
			return err
		}
		resultLocation = buildOutput
	}

	if buildType.IsVM() && !dryBuild {
		matches, err := filepath.Glob(fmt.Sprintf("%v/bin/run-*-vm", resultLocation))
		if err != nil || len(matches) == 0 {
			msg := fmt.Sprintf("Failed to find VM binary; look in %v for the script to run the VM.", resultLocation)
			log.Errorf(msg)
			return fmt.Errorf("%v", msg)
		}
		log.Printf("Done. The virtual machine can be started by running `%v`.\n", matches[0])
		return nil
	}

	if buildType == buildTypeSystem {
		if opts.Verbose {
			log.Infof("this is a dry build, no activation will be performed")
		}
		return nil
	}

	log.Step("Comparing changes...")

	err := generation.RunDiffCommand(log, s, constants.CurrentSystem, resultLocation, &generation.DiffCommandOptions{
		UseNvd:  cfg.UseNvd,
		Verbose: opts.Verbose,
	})
	if err != nil {
		log.Errorf("failed to run diff command: %v", err)
	}

	if !opts.AlwaysConfirm {
		log.Printf("\n")
		confirm, err := cmdUtils.ConfirmationInput("Activate this configuration?")
		if err != nil {
			log.Errorf("failed to get confirmation: %v", err)
			return err
		}
		if !confirm {
			msg := "confirmation was not given, skipping activation"
			log.Warn(msg)
			return fmt.Errorf("%v", msg)
		}
	}

	log.Step("Activating...")

	return nil
}
