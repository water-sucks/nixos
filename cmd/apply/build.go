package apply

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/water-sucks/nixos/internal/cmd/nixopts"
	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	"github.com/water-sucks/nixos/internal/configuration"
	"github.com/water-sucks/nixos/internal/constants"
	"github.com/water-sucks/nixos/internal/logger"
	"github.com/water-sucks/nixos/internal/system"
)

type buildType int

const (
	buildTypeSystem buildType = iota
	buildTypeSystemActivation
	buildTypeVM
	buildTypeVMWithBootloader
)

func (b buildType) BuildAttr() string {
	switch b {
	case buildTypeSystem, buildTypeSystemActivation:
		return "toplevel"
	case buildTypeVM:
		return "vm"
	case buildTypeVMWithBootloader:
		return "vmWithBootLoader"
	default:
		panic("unknown build type")
	}
}

func (b buildType) IsVM() bool {
	return b == buildTypeVM || b == buildTypeVMWithBootloader
}

func (b buildType) IsSystem() bool {
	return b == buildTypeSystem || b == buildTypeSystemActivation
}

type buildOptions struct {
	NixOpts        *cmdTypes.ApplyNixOptions
	ResultLocation string
	DryBuild       bool
	UseNom         bool
	GenerationTag  string
	Verbose        bool
}

func buildFlake(s system.CommandRunner, log *logger.Logger, flakeRef *configuration.FlakeRef, buildType buildType, opts *buildOptions) (string, error) {
	if flakeRef == nil {
		return "", fmt.Errorf("no flake ref provided")
	}

	nixCommand := "nix"
	if opts.UseNom {
		nixCommand = "nom"
	}

	systemAttribute := fmt.Sprintf("%s#nixosConfigurations.%s.config.system.build.%s", flakeRef.URI, flakeRef.System, buildType.BuildAttr())

	argv := []string{nixCommand, "build", systemAttribute, "--print-out-paths"}

	if opts.ResultLocation != "" {
		argv = append(argv, "--out-link", opts.ResultLocation)
	} else {
		argv = append(argv, "--no-link")
	}

	if opts.DryBuild {
		argv = append(argv, "--dry-run")
	}

	if opts.NixOpts != nil {
		argv = append(argv, nixopts.NixOptionsToArgsList(opts.NixOpts)...)
	}

	if opts.Verbose {
		log.CmdArray(argv)
	}

	var stdout bytes.Buffer
	cmd := system.NewCommand(nixCommand, argv[1:]...)
	cmd.Stdout = &stdout

	if opts.GenerationTag != "" {
		cmd.SetEnv("NIXOS_GENERATION_TAG", opts.GenerationTag)
	}

	_, err := s.Run(cmd)

	return strings.Trim(stdout.String(), "\n "), err
}

func buildLegacy(s system.CommandRunner, log *logger.Logger, buildType buildType, opts *buildOptions) (string, error) {
	nixCommand := "nix-build"
	if opts.UseNom {
		nixCommand = "nom-build"
	}

	argv := []string{nixCommand, "<nixpkgs/nixos>", "-A", buildType.BuildAttr()}

	// Mimic `nixos-rebuild` behavior of using -k option
	// for all commands except for switch and boot
	if buildType != buildTypeSystemActivation {
		argv = append(argv, "-k")
	}

	if opts.NixOpts != nil {
		argv = append(argv, nixopts.NixOptionsToArgsList(opts.NixOpts)...)
	}

	if opts.Verbose {
		log.CmdArray(argv)
	}

	var stdout bytes.Buffer
	cmd := system.NewCommand(nixCommand, argv[1:]...)
	cmd.Stdout = &stdout

	if opts.GenerationTag != "" {
		cmd.SetEnv("NIXOS_GENERATION_TAG", opts.GenerationTag)
	}

	_, err := s.Run(cmd)

	return strings.Trim(stdout.String(), "\n "), err
}

const channelDirectory = constants.NixProfileDirectory + "/per-user/root/channels"

func upgradeChannels(s system.CommandRunner, log *logger.Logger, verbose bool, upgradeAll bool) error {
	argv := []string{"nix-channel", "--update"}

	if !upgradeAll {
		// Always upgrade the `nixos` channel, as well as any channels that
		// have the ".update-on-nixos-rebuild" marker file in them.
		argv = append(argv, "nixos")

		entries, err := os.ReadDir(channelDirectory)
		if err != nil {
			return err
		}

		for _, entry := range entries {
			if entry.IsDir() {
				if _, err := os.Stat(filepath.Join(channelDirectory, entry.Name(), ".update-on-nixos-rebuild")); err == nil {
					argv = append(argv, entry.Name())
				}
			}
		}
	}

	if verbose {
		log.CmdArray(argv)
	}

	cmd := system.NewCommand(argv[0], argv[1:]...)
	_, err := s.Run(cmd)
	return err
}
