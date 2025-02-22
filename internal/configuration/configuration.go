package configuration

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	buildOpts "github.com/water-sucks/nixos/internal/build"
	"github.com/water-sucks/nixos/internal/logger"
	"github.com/water-sucks/nixos/internal/settings"
)

type Configuration interface {
	EvalAttribute(attr string) (*string, error)
}

type LegacyConfiguration struct {
	Includes      []string
	ConfigDirname string
}

type FlakeRef struct {
	URI    string
	System string
}

type AttributeEvaluationError struct {
	Attribute        string
	EvaluationOutput string
}

func (e *AttributeEvaluationError) Error() string {
	return fmt.Sprintf("failed to evaluate attribute %s", e.Attribute)
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

func FindLegacyConfiguration(log *logger.Logger, includes []string, verbose bool) (string, error) {
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
			return "", fmt.Errorf("expected 'nixos-config' attribute to exist in NIX_PATH")
		}
	}

	configFileStat, err := os.Stat(configuration)
	if err != nil {
		return "", err
	}

	if configFileStat.IsDir() {
		defaultNix := filepath.Join(configuration, "default.nix")

		info, err := os.Stat(defaultNix)
		if err != nil {
			return "", err
		}

		if info.IsDir() {
			return "", fmt.Errorf("%v is a directory, not a file", defaultNix)
		}
	}

	return configuration, nil
}

func FindConfiguration(log *logger.Logger, cfg *settings.Settings, includes []string, verbose bool) (Configuration, error) {
	if buildOpts.Flake == "true" {
		if verbose {
			log.Info("looking for flake configuration")
		}

		f, err := FlakeRefFromEnv(cfg.ConfigLocation)
		if err != nil {
			return nil, err
		}

		if err := f.InferSystemFromHostnameIfNeeded(); err != nil {
			return nil, err
		}

		if verbose {
			log.Infof("found flake configuration: %s#%s", f.URI, f.System)
		}

		return f, nil
	} else {
		c, err := FindLegacyConfiguration(log, includes, verbose)
		if err != nil {
			return nil, err
		}

		if verbose {
			log.Infof("found legacy configuration at %s", c)
		}

		return &LegacyConfiguration{
			Includes:      includes,
			ConfigDirname: c,
		}, nil
	}
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

func (f *FlakeRef) EvalAttribute(attr string) (*string, error) {
	evalArg := fmt.Sprintf(`%s#nixosConfigurations.%s.config.%s`, f.URI, f.System, attr)
	argv := []string{"nix", "eval", evalArg}

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
