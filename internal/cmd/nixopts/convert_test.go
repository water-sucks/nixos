package nixopts_test

import (
	"reflect"
	"testing"

	"github.com/spf13/cobra"
	"github.com/water-sucks/nixos/internal/cmd/nixopts"
)

type nixOptions struct {
	Quiet          bool
	PrintBuildLogs bool
	MaxJobs        int
	LogFormat      string
	Builders       []string
	Options        map[string]string
}

func createTestCmd() (*cobra.Command, *nixOptions) {
	opts := nixOptions{}

	cmd := &cobra.Command{}

	nixopts.AddQuietNixOption(cmd, &opts.Quiet)
	nixopts.AddPrintBuildLogsNixOption(cmd, &opts.PrintBuildLogs)
	nixopts.AddMaxJobsNixOption(cmd, &opts.MaxJobs)
	nixopts.AddLogFormatNixOption(cmd, &opts.LogFormat)
	nixopts.AddBuildersNixOption(cmd, &opts.Builders)
	nixopts.AddOptionNixOption(cmd, &opts.Options)

	return cmd, &opts
}

func TestNixOptionsToArgsList(t *testing.T) {
	tests := []struct {
		name string
		// The command-line arguments passed to Cobra
		passedArgs []string
		// The expected arguments to be passed to Nix
		expected []string
	}{
		{
			name:       "All fields zero-valued",
			passedArgs: []string{},
			expected:   []string{},
		},
		{
			name:       "Single boolean field",
			passedArgs: []string{"--quiet"},
			expected:   []string{"--quiet"},
		},
		{
			name:       "Integer field set",
			passedArgs: []string{"--max-jobs", "4"},
			expected:   []string{"--max-jobs", "4"},
		},
		{
			name:       "Integer field set to zero value",
			passedArgs: []string{"--max-jobs", "0"},
			expected:   []string{"--max-jobs", "0"},
		},
		{
			name:       "String field set",
			passedArgs: []string{"--log-format", "json"},
			expected:   []string{"--log-format", "json"},
		},
		{
			name:       "Slice field set",
			passedArgs: []string{"--builders", "builder1", "--builders", "builder2"},
			expected:   []string{"--builders", "builder1", "--builders", "builder2"},
		},
		{
			name:       "Map field set",
			passedArgs: []string{"--option", "option1=value1", "--option", "option2=value2"},
			expected:   []string{"--option", "option1", "value1", "--option", "option2", "value2"},
		},
		{
			name:       "Mixed fields set",
			passedArgs: []string{"--quiet", "--max-jobs", "2", "--log-format", "xml", "--builders", "builder1", "--option", "option1=value1", "--option", "option2=value2"},
			expected:   []string{"--quiet", "--max-jobs", "2", "--log-format", "xml", "--builders", "builder1", "--option", "option1", "value1", "--option", "option2", "value2"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cmd, opts := createTestCmd()

			// Dummy execution of "command" for Cobra to parse flags
			cmd.SetArgs(tt.passedArgs)
			_ = cmd.Execute()

			args := nixopts.NixOptionsToArgsList(cmd.Flags(), opts)

			if !reflect.DeepEqual(args, tt.expected) {
				t.Errorf("NixOptionsToArgsList() = %v, want %v", args, tt.expected)
			}
		})
	}
}
