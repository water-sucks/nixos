package activation

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/water-sucks/nixos/internal/constants"
	"github.com/water-sucks/nixos/internal/generation"
	"github.com/water-sucks/nixos/internal/logger"
	"github.com/water-sucks/nixos/internal/system"
)

func EnsureSystemProfileDirectoryExists() error {
	// The system profile directory sometimes doesn't exist,
	// and does need to be manually created if this is the case.
	// This kinda sucks, since it requires root execution, but
	// there's not really a better way to ensure that this
	// profile's directory exists.

	err := os.MkdirAll(constants.NixSystemProfileDirectory, 0o755)
	if err != nil {
		if err != os.ErrExist {
			return fmt.Errorf("failed to create nix system profile directory: %w", err)
		}
	}

	return nil
}

func SetNixEnvProfile(s system.CommandRunner, log *logger.Logger, profile string, closure string, verbose bool) error {
	if profile != "system" {
		err := EnsureSystemProfileDirectoryExists()
		if err != nil {
			return err
		}
	}

	profileDirectory := generation.GetProfileDirectoryFromName(profile)

	argv := []string{"nix-env", "--profile", profileDirectory, "--set", closure}

	if verbose {
		log.CmdArray(argv)
	}

	cmd := system.NewCommand(argv[0], argv[1:]...)

	_, err := s.Run(cmd)

	return err
}

func RollbackNixEnvProfile(s system.CommandRunner, log *logger.Logger, profile string, verbose bool) error {
	if profile != "system" {
		err := EnsureSystemProfileDirectoryExists()
		if err != nil {
			return err
		}
	}

	profileDirectory := generation.GetProfileDirectoryFromName(profile)

	argv := []string{"nix-env", "--profile", profileDirectory, "--rollback"}

	if verbose {
		log.CmdArray(argv)
	}

	cmd := system.NewCommand(argv[0], argv[1:]...)

	_, err := s.Run(cmd)

	return err
}

type SwitchToConfigurationAction int

const (
	SwitchToConfigurationActionSwitch = iota
	SwitchToConfigurationActionBoot
	SwitchToConfigurationActionTest
	SwitchToConfigurationActionDryActivate
)

func (c SwitchToConfigurationAction) String() string {
	switch c {
	case SwitchToConfigurationActionSwitch:
		return "switch"
	case SwitchToConfigurationActionBoot:
		return "boot"
	case SwitchToConfigurationActionTest:
		return "test"
	case SwitchToConfigurationActionDryActivate:
		return "dry-activate"
	default:
		panic("unknown switch to configuration action type")
	}
}

type SwitchToConfigurationOptions struct {
	InstallBootloader bool
	Verbose           bool
}

func SwitchToConfiguration(s system.CommandRunner, log *logger.Logger, generationLocation string, action SwitchToConfigurationAction, opts *SwitchToConfigurationOptions) error {
	commandPath := filepath.Join(generationLocation, "bin", "switch-to-configuration")

	argv := []string{commandPath, action.String()}

	if opts.Verbose {
		log.CmdArray(argv)
	}

	cmd := system.NewCommand(argv[0], argv[1:]...)
	if opts.InstallBootloader {
		cmd.SetEnv("NIXOS_INSTALL_BOOTLOADER", "1")
	}

	_, err := s.Run(cmd)

	return err
}
