package config_test

import (
	"math"
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
			Option: config.OptionConfig{
				MaxRank: 0.5,
			},
		}

		errs := cfg.Validate()
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
			Option: config.OptionConfig{
				MaxRank: 2,
			},
		}

		errs := cfg.Validate()
		if errs != nil {
			t.Errorf("expected error slice to be nil, got %d errors", len(errs))
		}
	})
}

func almostEqual(a float64, b float64) bool {
	const float64EqualityThreshold = 1e-9
	return math.Abs(a-b) <= float64EqualityThreshold
}

func TestSetConfigValue(t *testing.T) {
	t.Run("Set float field successfully", func(t *testing.T) {
		cfg := &config.Config{
			Option: config.OptionConfig{
				MaxRank: 1.00,
			},
		}

		err := cfg.SetValue("option.max_rank", "4.5")
		if err != nil {
			t.Fatalf("expected option.max_rank to be set, err = %v", err)
		}

		expected := 4.5
		actual := cfg.Option.MaxRank

		if !almostEqual(expected, actual) {
			t.Fatalf("expected option.max_rank = %v, actual = %v", expected, actual)
		}
	})

	t.Run("Set string field successfully", func(t *testing.T) {
		cfg := &config.Config{
			ConfigLocation: "/etc/nixos",
		}

		err := cfg.SetValue("config_location", "/home/user")
		if err != nil {
			t.Fatalf("expected config_location to be set, err = %v", err)
		}

		expected := "/home/user"
		actual := cfg.ConfigLocation

		if expected != actual {
			t.Fatalf("expected config_location = %v, actual = %v", expected, actual)
		}
	})

	t.Run("Set boolean field successfully", func(t *testing.T) {
		cfg := &config.Config{
			Apply: config.ApplyConfig{
				ImplyImpureWithTag: true,
			},
		}

		err := cfg.SetValue("apply.imply_impure_with_tag", "true")
		if err != nil {
			t.Fatalf("expected apply.imply_impure_with_tag to be set, err = %v", err)
		}

		expected := true
		actual := cfg.Apply.ImplyImpureWithTag

		if expected != actual {
			t.Fatalf("expected apply.imply_impure_with_tag = %v, actual = %v", expected, actual)
		}
	})

	t.Run("Invalid key", func(t *testing.T) {
		cfg := &config.Config{}

		err := cfg.SetValue("invalid_key", "")
		if err == nil {
			t.Fatalf("expected invalid_key to error out, no errors detected")
		}
	})

	t.Run("Invalid nested key", func(t *testing.T) {
		cfg := &config.Config{}

		err := cfg.SetValue("apply.invalid.nested", "")
		if err == nil {
			t.Fatalf("expected apply.invalid.nested to error out, no errors detected")
		}
	})

	t.Run("Invalid boolean value", func(t *testing.T) {
		cfg := &config.Config{
			Apply: config.ApplyConfig{
				ImplyImpureWithTag: true,
			},
		}

		err := cfg.SetValue("apply.imply_impure_with_tag", "invalid")
		if err == nil {
			t.Fatalf("expected apply.imply_impure_with_tag to error out, no errors detected")
		}
	})

	t.Run("Invalid float value", func(t *testing.T) {
		cfg := &config.Config{
			Option: config.OptionConfig{
				MaxRank: 1.00,
			},
		}

		err := cfg.SetValue("option.max_rank", "invalid")
		if err == nil {
			t.Fatalf("expected option.max_rank to error out, no errors detected")
		}

		expected := 1.00
		actual := cfg.Option.MaxRank

		if !almostEqual(expected, actual) {
			t.Fatalf("expected option.max_rank to remain unchanged, expected = %v actual = %v", expected, actual)
		}
	})
}
