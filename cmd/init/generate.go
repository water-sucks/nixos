package init

import (
	_ "embed"
	"fmt"

	buildOpts "github.com/water-sucks/nixos/internal/build"
	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	"github.com/water-sucks/nixos/internal/config"
	"github.com/water-sucks/nixos/internal/logger"
	"github.com/water-sucks/nixos/internal/system"
)

//go:embed hardware_configuration.nix.txt
var hardwareConfigurationNixTemplate string

//go:embed configuration.nix.txt
var configurationNixTemplate string

//go:embed flake.nix.txt
var flakeNixTemplate string

func generateHwConfigNix(s system.CommandRunner, log *logger.Logger, cfg *config.Config, opts *cmdTypes.InitOpts, virtType VirtualisationType) (string, error) {
	cpuInfo := getCPUInfo(log)

	log.Infof("detected CPU type: %v", cpuInfo.Manufacturer.CPUType())
	log.Infof("KVM virtualisation enabled: %v", cpuInfo.Virtualised)
	log.Infof("virtualisation type of current host: %v", virtType)

	imports := []string{}
	initrdAvailableModules := []string{}
	initrdModules := []string{}
	kernelModules := []string{}
	modulePackages := []string{}
	attrs := []KVPair{}

	hwConfigSettings := hardwareConfigSettings{
		Imports:               &imports,
		InitrdAvailableMdules: &initrdAvailableModules,
		InitrdModules:         &initrdModules,
		KernelModules:         &kernelModules,
		ModulePackages:        &modulePackages,
		Attrs:                 &attrs,
	}
	_ = hwConfigSettings

	if cfg.Init.ExtraAttrs != nil {
		for k, v := range cfg.Init.ExtraAttrs {
			attrs = append(attrs, KVPair{Key: k, Value: v})
		}
	}

	return fmt.Sprintf(
		hardwareConfigurationNixTemplate,
		"", // TODO: imports
		"", // TODO: available initrd modules
		"", // TODO: initrd modules
		"", // TODO: kernel modules
		"", // TODO: module packages
		"", // TODO: filesystems
		"", // TODO: swap devices
		"", // TODO: networking attrs
		"", // TODO: other attrs
	), nil
}

func generateConfigNix(s system.CommandRunner, log *logger.Logger, virtType VirtualisationType) (string, error) {
	return fmt.Sprintf(
		configurationNixTemplate,
		"", // TODO: bootloader config
		"", // TODO: xserver config
		"", // TODO: desktop config
		"", // TODO: extra config
		buildOpts.NixpkgsVersion,
	), nil
}

func generateFlakeNix() string {
	nixpkgsInputLine := fmt.Sprintf(`nixpkgs.url = "github:NixOS/nixpkgs/release-%v";`, buildOpts.NixpkgsVersion)
	return fmt.Sprintf(flakeNixTemplate, nixpkgsInputLine)
}

type KVPair struct {
	Key   string
	Value string
}

type hardwareConfigSettings struct {
	Imports               *[]string
	InitrdAvailableMdules *[]string
	InitrdModules         *[]string
	KernelModules         *[]string
	ModulePackages        *[]string
	Attrs                 *[]KVPair
}
