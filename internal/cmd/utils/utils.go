package cmd

import (
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"
)

func SetHelpFlagText(cmd *cobra.Command) {
	cmd.Flags().BoolP("help", "h", false, "Show this help menu")
}

func EscapeAndJoinArgs(args []string) string {
	var escapedArgs []string

	for _, arg := range args {
		if strings.ContainsAny(arg, " \t\n\"'\\") {
			arg = strings.ReplaceAll(arg, "\\", "\\\\")
			arg = strings.ReplaceAll(arg, "\"", "\\\"")
			escapedArgs = append(escapedArgs, fmt.Sprintf("\"%s\"", arg))
		} else {
			escapedArgs = append(escapedArgs, arg)
		}
	}

	return strings.Join(escapedArgs, " ")
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
