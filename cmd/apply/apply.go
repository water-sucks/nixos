package cmd

import (
	"fmt"
	"os"
	"os/exec"

	"github.com/spf13/cobra"
	buildOpts "github.com/water-sucks/nixos/internal/build"
	"github.com/water-sucks/nixos/internal/cmd/nixopts"
	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
	"github.com/water-sucks/nixos/internal/config"
	"github.com/water-sucks/nixos/internal/configuration"
	"github.com/water-sucks/nixos/internal/logger"
	"github.com/water-sucks/nixos/internal/utils"
)

type buildType int

const (
	buildTypeSystem buildType = iota
	buildTypeSystemActivation
	buildTypeVM
	buildTypeVMWithBootloader
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
		err := utils.ExecAsRoot(log, cfg.RootCommand)
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
	_ = useNom

	return nil
}
