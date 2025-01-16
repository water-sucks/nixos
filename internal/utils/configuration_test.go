package utils_test

import (
	"reflect"
	"testing"

	"github.com/water-sucks/nixos/internal/utils"
)

func TestFlakeRefFromString(t *testing.T) {
	tests := []struct {
		input    string
		expected *utils.FlakeRef
	}{
		{
			input: "github:owner/repo#linux",
			expected: &utils.FlakeRef{
				URI:    "github:owner/repo",
				System: "linux",
			},
		},
		{
			input: "github:owner/repo",
			expected: &utils.FlakeRef{
				URI:    "github:owner/repo",
				System: "",
			},
		},
		{
			input: "github:owner/repo#",
			expected: &utils.FlakeRef{
				URI:    "github:owner/repo",
				System: "",
			},
		},
		{
			input: "#linux",
			expected: &utils.FlakeRef{
				URI:    "",
				System: "linux",
			},
		},
		{
			input: "",
			expected: &utils.FlakeRef{
				URI:    "",
				System: "",
			},
		},
		{
			input: "github:owner/repo#linux#extra",
			expected: &utils.FlakeRef{
				URI:    "github:owner/repo",
				System: "linux#extra",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			result := utils.FlakeRefFromString(tt.input)

			if !reflect.DeepEqual(result, tt.expected) {
				t.Errorf("FlakeRefFromString(%q) = %+v, want %+v", tt.input, result, tt.expected)
			}
		})
	}
}
