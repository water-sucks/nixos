package switch_cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"

	"github.com/spf13/cobra"

	"github.com/water-sucks/nixos/internal/activation"
	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
	"github.com/water-sucks/nixos/internal/config"
	"github.com/water-sucks/nixos/internal/constants"
	"github.com/water-sucks/nixos/internal/generation"
	"github.com/water-sucks/nixos/internal/logger"
	"github.com/water-sucks/nixos/internal/system"
	"github.com/water-sucks/nixos/internal/utils"
)

func GenerationSwitchCommand(genOpts *cmdTypes.GenerationOpts) *cobra.Command {
	opts := cmdTypes.GenerationSwitchOpts{}

	cmd := cobra.Command{
		Use:   "switch [flags] {GEN}",
		Short: "Activate an existing generation",
		Long:  "Activate an arbitrary existing NixOS generation",
		Args: func(cmd *cobra.Command, args []string) error {
			if err := cobra.ExactArgs(1)(cmd, args); err != nil {
				return err
			}

			arg := args[0]
			gen, err := strconv.ParseInt(arg, 10, 32)
			if err != nil {
				return fmt.Errorf("{GEN} must be integer value, got '%v'", arg)
			}
			opts.Generation = uint(gen)

			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			return cmdUtils.CommandErrorHandler(generationSwitchMain(cmd, genOpts, &opts))
		},
	}

	cmd.Flags().BoolVarP(&opts.Dry, "dry", "d", false, "Show what would be activated, but do not activate")
	cmd.Flags().StringVarP(&opts.Specialisation, "specialisation", "s", "", "Activate the specialisation with `name`")
	cmd.Flags().BoolVarP(&opts.Verbose, "verbose", "v", false, "Show verbose logging")
	cmd.Flags().BoolVarP(&opts.AlwaysConfirm, "yes", "y", false, "Automatically confirm activation")

	cmdUtils.SetHelpFlagText(&cmd)
	cmd.SetHelpTemplate(cmd.HelpTemplate() + `
Arguments:
    [GEN]       Generation number
`)

	return &cmd
}

func generationSwitchMain(cmd *cobra.Command, genOpts *cmdTypes.GenerationOpts, opts *cmdTypes.GenerationSwitchOpts) error {
	log := logger.FromContext(cmd.Context())
	cfg := config.FromContext(cmd.Context())
	s := system.NewLocalSystem()

	if os.Geteuid() != 0 {
		err := utils.ExecAsRoot(cfg.RootCommand)
		if err != nil {
			log.Errorf("failed to re-exec command as root: %v", err)
			return err
		}
	}

	profileDirectory := constants.NixProfileDirectory
	if genOpts.ProfileName != "system" {
		profileDirectory = constants.NixSystemProfileDirectory
	}
	generationLink := filepath.Join(profileDirectory, fmt.Sprintf("%v-%v-link", genOpts.ProfileName, opts.Generation))

	// Check if generation exists. There are rare cases in which a Nix profile can
	// point to a nonexistent store path, such as in the case that someone manually
	// deletes stuff, but this shouldn't really happen much, if at all.
	if _, err := os.Stat(generationLink); err != nil {
		if os.IsNotExist(err) {
			msg := fmt.Sprintf("generation %v not found", opts.Generation)
			log.Error(msg)
			return fmt.Errorf("%v", msg)
		}

		log.Errorf("failed to access generation link: %v", err)
		return err
	}

	log.Step("Comparing changes...")

	err := generation.RunDiffCommand(log, s, constants.CurrentSystem, generationLink, &generation.DiffCommandOptions{
		UseNvd:  cfg.UseNvd,
		Verbose: opts.Verbose,
	})
	if err != nil {
		log.Errorf("failed to run diff command: %v", err)
	}

	if !opts.AlwaysConfirm {
		log.Printf("\n")
		confirm, err := cmdUtils.ConfirmationInput("Activate this generation?")
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

	specialisation := opts.Specialisation
	if specialisation == "" {
		defaultSpecialisation, err := activation.FindDefaultSpecialisationFromConfig(generationLink)
		if err != nil {
			log.Warnf("unable to find default specialisation from config: %v", err)
		} else {
			specialisation = defaultSpecialisation
		}
	}

	if !activation.VerifySpecialisationExists(generationLink, specialisation) {
		log.Warnf("specialisation '%v' does not exist", specialisation)
		log.Warn("using base configuration without specialisations")
		specialisation = ""
	}

	previousGenNumber, err := activation.GetCurrentGenerationNumber(genOpts.ProfileName)
	if err != nil {
		log.Errorf("%v", err)
		return err
	}

	if !opts.Dry {
		log.Step("Setting system profile...")

		if err := activation.SetNixProfileGeneration(s, log, genOpts.ProfileName, uint64(opts.Generation), opts.Verbose); err != nil {
			log.Errorf("failed to set system profile: %v", err)
			return err
		}
	}

	// In case switch-to-configuration fails, rollback the profile.
	// This is to prevent accidental deletion of all working
	// generations in case the switch-to-configuration script
	// fails, since the active profile will not be rolled back
	// automatically.
	rollbackProfile := false
	if !opts.Dry {
		defer func(rollback *bool) {
			if !*rollback {
				return
			}

			log.Step("Rolling back system profile...")
			if err := activation.SetNixProfileGeneration(s, log, "system", previousGenNumber, opts.Verbose); err != nil {
				log.Errorf("failed to rollback system profile: %v", err)
				log.Info("make sure to rollback the system manually before deleting anything!")
			}
		}(&rollbackProfile)
	}

	log.Step("Activating...")

	var stcAction activation.SwitchToConfigurationAction = activation.SwitchToConfigurationActionSwitch
	if opts.Dry {
		stcAction = activation.SwitchToConfigurationActionDryActivate
	}

	err = activation.SwitchToConfiguration(s, log, generationLink, stcAction, &activation.SwitchToConfigurationOptions{
		Verbose:        opts.Verbose,
		Specialisation: specialisation,
	})
	if err != nil {
		rollbackProfile = true
		log.Errorf("failed to switch to configuration: %v", err)
		return err
	}

	return nil
}
