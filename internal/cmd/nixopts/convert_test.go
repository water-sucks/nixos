package nixopts_test

import (
	"reflect"
	"testing"

	"github.com/water-sucks/nixos/internal/cmd/nixopts"
)

func TestNixOptionsToArgsList(t *testing.T) {
	type nixOptions struct {
		Quiet          bool
		PrintBuildLogs bool
		MaxJobs        int
		LogFormat      string
		Builders       []string
		Options        map[string]string
	}

	tests := []struct {
		name     string
		options  *nixOptions
		expected []string
	}{
		{
			name:     "All fields zero-valued",
			options:  &nixOptions{},
			expected: []string{},
		},
		{
			name: "Single boolean field",
			options: &nixOptions{
				Quiet: true,
			},
			expected: []string{"--quiet"},
		},
		{
			name: "Integer field set",
			options: &nixOptions{
				MaxJobs: 4,
			},
			expected: []string{"--max-jobs", "4"},
		},
		{
			name: "String field set",
			options: &nixOptions{
				LogFormat: "json",
			},
			expected: []string{"--log-format", "json"},
		},
		{
			name: "Slice field set",
			options: &nixOptions{
				Builders: []string{"builder1", "builder2"},
			},
			expected: []string{"--builders", "builder1", "--builders", "builder2"},
		},
		{
			name: "Map field set",
			options: &nixOptions{
				Options: map[string]string{"option1": "value1", "option2": "value2"},
			},
			expected: []string{"--option", "option1", "value1", "--option", "option2", "value2"},
		},
		{
			name: "Mixed fields set",
			options: &nixOptions{
				Quiet:     true,
				MaxJobs:   2,
				LogFormat: "xml",
				Builders:  []string{"builder1"},
			},
			expected: []string{"--quiet", "--max-jobs", "2", "--log-format", "xml", "--builders", "builder1"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			args := nixopts.NixOptionsToArgsList(tt.options)
			if !reflect.DeepEqual(args, tt.expected) {
				t.Errorf("NixOptionsToArgsList() = %v, want %v", args, tt.expected)
			}
		})
	}
}
