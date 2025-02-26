package configuration

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/water-sucks/nixos/internal/logger"
)

type LegacyConfiguration struct {
	Includes      []string
	ConfigDirname string
}

func FindLegacyConfiguration(log *logger.Logger, includes []string, verbose bool) (*LegacyConfiguration, error) {
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

	if configuration == "" && includes != nil {
		for _, include := range includes {
			if strings.HasPrefix(include, "nixos-config=") {
				configuration = strings.TrimPrefix(include, "nixos-config=")
				break
			}
		}
	}

	if configuration == "" {
		if verbose {
			log.Infof("$NIXOS_CONFIG not set, using $NIX_PATH to find configuration")
		}

		nixPath := strings.Split(os.Getenv("NIX_PATH"), ":")
		for _, entry := range nixPath {
			if strings.HasPrefix(entry, "nixos-config=") {
				configuration = strings.TrimPrefix(entry, "nixos-config=")
				break
			}
		}

		if configuration == "" {
			return nil, fmt.Errorf("expected 'nixos-config' attribute to exist in NIX_PATH")
		}
	}

	configFileStat, err := os.Stat(configuration)
	if err != nil {
		return nil, err
	}

	if configFileStat.IsDir() {
		defaultNix := filepath.Join(configuration, "default.nix")

		info, err := os.Stat(defaultNix)
		if err != nil {
			return nil, err
		}

		if info.IsDir() {
			return nil, fmt.Errorf("%v is a directory, not a file", defaultNix)
		}
	}

	return &LegacyConfiguration{
		Includes:      includes,
		ConfigDirname: configuration,
	}, nil
}

func (l *LegacyConfiguration) EvalAttribute(attr string) (*string, error) {
	configAttr := fmt.Sprintf("config.%s", attr)
	argv := []string{"nix-instantiate", "--eval", "<nixpkgs/nixos>", "-A", configAttr}

	for _, v := range l.Includes {
		argv = append(argv, "-I", v)
	}

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	if err != nil {
		return nil, &AttributeEvaluationError{
			Attribute:        attr,
			EvaluationOutput: strings.TrimSpace(stderr.String()),
		}
	}

	value := strings.TrimSpace(stdout.String())

	return &value, nil
}
