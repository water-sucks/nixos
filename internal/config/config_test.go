package config_test

import (
	"testing"

	"github.com/water-sucks/nixos/internal/config"
)

func TestValidateConfig(t *testing.T) {
	t.Run("incorrect config fails", func(t *testing.T) {
		cfg := &config.Config{
			Aliases: map[string][]string{
				"":                     {"value1"},
				"-bad":                 {"value2"},
				"has space":            {"value3"},
				"validalias":           {"value4"},
				"validalias-noentries": {},
			},
			Option: &config.OptionConfig{
				MaxRank: 0.5,
			},
		}

		errs := config.ValidateConfig(cfg)
		if len(errs) != 5 {
			t.Errorf("expected 5 errors, got %d", len(errs))
		}

		if len(cfg.Aliases) != 1 {
			t.Errorf("expected Aliases to have one valid entry, got %v", cfg.Aliases)
		}

		if cfg.Option.MaxRank != 3.00 {
			t.Errorf("expected Option.MaxRank to be reset to 3.00, got %f", cfg.Option.MaxRank)
		}
	})

	t.Run("valid config passes", func(t *testing.T) {
		cfg := &config.Config{
			Aliases: map[string][]string{
				"validalias": {"value1", "value2"},
			},
			Option: &config.OptionConfig{
				MaxRank: 2,
			},
		}

		errs := config.ValidateConfig(cfg)
		if errs != nil {
			t.Errorf("expected error slice to be nil, got %d errors", len(errs))
		}
	})
}
