package configuration

import (
	"fmt"

	buildOpts "github.com/water-sucks/nixos/internal/build"
	"github.com/water-sucks/nixos/internal/logger"
	"github.com/water-sucks/nixos/internal/settings"
)

type Configuration interface {
	EvalAttribute(attr string) (*string, error)
}

type AttributeEvaluationError struct {
	Attribute        string
	EvaluationOutput string
}

func (e *AttributeEvaluationError) Error() string {
	return fmt.Sprintf("failed to evaluate attribute %s", e.Attribute)
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

		return c, nil
	}
}
