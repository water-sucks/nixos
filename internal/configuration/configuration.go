package configuration

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/water-sucks/nixos/internal/logger"
)

type FlakeRef struct {
	URI    string
	System string
}

func FlakeRefFromString(s string) *FlakeRef {
	split := strings.Index(s, "#")

	if split > -1 {
		return &FlakeRef{
			URI:    s[:split],
			System: s[split+1:],
		}
	}

	return &FlakeRef{
		URI:    s,
		System: "",
	}
}

func FlakeRefFromEnv(defaultLocation string) (*FlakeRef, error) {
	nixosConfig, set := os.LookupEnv("NIXOS_CONFIG")
	if !set {
		nixosConfig = defaultLocation
	}

	if nixosConfig == "" {
		return nil, fmt.Errorf("NIXOS_CONFIG is not set")
	}

	return FlakeRefFromString(nixosConfig), nil
}

func (f *FlakeRef) InferSystemFromHostnameIfNeeded() error {
	if f.System == "" {
		hostname, err := os.Hostname()
		if err != nil {
			return err
		}

		f.System = hostname
	}

	return nil
}

func FindLegacyConfiguration(log *logger.Logger, verbose bool) (string, error) {
	if verbose {
		log.Infof("looking for legacy configuration")
	}

	var configuration string
	if nixosCfg, set := os.LookupEnv("NIXOS_CONFIG"); set {
		if verbose {
			log.Info("$NIXOS_CONFIG is set, using automatically")
		}
		configuration = nixosCfg
	}

	if configuration == "" {
		if verbose {
			log.Infof("$NIXOS_CONFIG not set, using NIX_PATH to find configuration")
		}

		nixPath := strings.Split(os.Getenv("NIX_PATH"), ":")
		for _, entry := range nixPath {
			if strings.HasPrefix(entry, "nixos-config=") {
				configuration = strings.TrimPrefix(entry, "nixos-config=")
				break
			}
		}

		if configuration == "" {
			return "", fmt.Errorf("expected 'nixos-config' attribute to exist in NIX_PATH")
		}
	}

	configFileStat, err := os.Stat(configuration)
	if err != nil {
		return "", errors.Unwrap(err)
	}

	if configFileStat.IsDir() {
		defaultNix := filepath.Join(configuration, "default.nix")

		info, err := os.Stat(defaultNix)
		if err != nil {
			return "", errors.Unwrap(err)
		}

		if info.IsDir() {
			return "", fmt.Errorf("default.nix is a directory, not a file")
		}

		return configuration, nil
	}

	return configuration, nil
}
