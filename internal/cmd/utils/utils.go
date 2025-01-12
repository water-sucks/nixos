package cmd

import (
	"fmt"
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
