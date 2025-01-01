package cmd

import "github.com/spf13/cobra"

func SetHelpFlagText(cmd cobra.Command) {
	cmd.Flags().BoolP("help", "h", false, "Show this help menu")
}
