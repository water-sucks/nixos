package config_test

import (
	"strings"
	"testing"

	"github.com/spf13/cobra"
	"github.com/water-sucks/nixos/internal/config"
)

type TestCase struct {
	Input    string
	Expected []string
}

func TestCompleteConfigFlag(t *testing.T) {
	testCases := []TestCase{
		// Fields tagged with `noset:"true"` should result in no completions
		{"aliases", []string{}},
		{"ali", []string{}},
		{"init.extra_config", []string{}},

		// Fields with a single match to a settable key should add an = at the end.
		{"apply.imply_impure_with_tag", []string{"apply.imply_impure_with_tag="}},
		{"apply.imp", []string{"apply.imply_impure_with_tag="}},

		// Fields with further nested keys should add a .
		{"app", []string{"apply."}},
		{"ent", []string{"enter."}},

		// Fields after a . should be underneath the nested option
		{"option.", []string{"option.max_rank", "option.prettify"}},

		{"apply.use_", []string{"apply.use_nom", "apply.use_git_commit_msg"}},

		// Invalid fields should result in no completions
		{"invalid", []string{}},
		{"bruh.lmao", []string{}},

		// Boolean field value completion
		{"use_color=", []string{"use_color=true", "use_color=false"}},
		{"use_color=t", []string{"use_color=true"}},
		{"use_color=f", []string{"use_color=false"}},
		{"use_color=invalid", []string{}},
	}

	for _, testCase := range testCases {
		actual, _ := config.CompleteConfigFlag(&cobra.Command{}, []string{}, testCase.Input)

		// Discard completion descriptions.
		for i, v := range actual {
			actual[i] = stripAfterTab(v)
		}

		if !slicesEqual(actual, testCase.Expected) {
			t.Errorf("for input '%s': expected %v, got %v", testCase.Input, testCase.Expected, actual)
		}
	}
}

func slicesEqual(a []string, b []string) bool {
	if len(a) != len(b) {
		return false
	}

	for i, v := range a {
		if v != b[i] {
			return false
		}
	}

	return true
}

func stripAfterTab(input string) string {
	if i := strings.Index(input, "\t"); i > -1 {
		return input[:i]
	}
	return input
}
