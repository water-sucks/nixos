package configuration_test

import (
	"reflect"
	"testing"

	"github.com/nix-community/nixos-cli/internal/configuration"
)

func TestFlakeRefFromString(t *testing.T) {
	tests := []struct {
		input    string
		expected *configuration.FlakeRef
	}{
		{
			input: "github:owner/repo#linux",
			expected: &configuration.FlakeRef{
				URI:    "github:owner/repo",
				System: "linux",
			},
		},
		{
			input: "github:owner/repo",
			expected: &configuration.FlakeRef{
				URI:    "github:owner/repo",
				System: "",
			},
		},
		{
			input: "github:owner/repo#",
			expected: &configuration.FlakeRef{
				URI:    "github:owner/repo",
				System: "",
			},
		},
		{
			input: "#linux",
			expected: &configuration.FlakeRef{
				URI:    "",
				System: "linux",
			},
		},
		{
			input: "",
			expected: &configuration.FlakeRef{
				URI:    "",
				System: "",
			},
		},
		{
			input: "github:owner/repo#linux#extra",
			expected: &configuration.FlakeRef{
				URI:    "github:owner/repo",
				System: "linux#extra",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			result := configuration.FlakeRefFromString(tt.input)

			if !reflect.DeepEqual(result, tt.expected) {
				t.Errorf("FlakeRefFromString(%q) = %+v, want %+v", tt.input, result, tt.expected)
			}
		})
	}
}
