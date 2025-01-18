package utils

import (
	"errors"
	"os"

	"github.com/spf13/cobra"
)

func SetHelpFlagText(cmd *cobra.Command) {
	cmd.Flags().BoolP("help", "h", false, "Show this help menu")
}

var CommandError = errors.New("command error")

// Replace a returned error with the generic CommandError, and.
// exit with a non-zero exit code. This is to avoid extra error
// messages being printed when a command function defined with
// RunE returns a non-nil error.
func CommandErrorHandler(err error) error {
	if err != nil {
		os.Exit(1)

		return CommandError
	}
	return nil
}
