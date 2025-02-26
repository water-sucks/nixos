package configuration

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strings"
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
