package cmd

import (
	"os"

	"github.com/spf13/cobra"
)

func completionCmd() *cobra.Command {
	cmd := cobra.Command{
		Use:                   "completion {bash|zsh|fish}",
		Short:                 "Generate completion scripts",
		Long:                  "Generate completion scripts for use in shells.",
		Hidden:                true,
		DisableFlagsInUseLine: true,
		ValidArgs:             []string{"bash", "zsh", "fish"},
		Args:                  cobra.MatchAll(cobra.ExactArgs(1), cobra.OnlyValidArgs),
		Run: func(cmd *cobra.Command, args []string) {
			switch args[0] {
			case "bash":
				_ = cmd.Root().GenBashCompletion(os.Stdout)
			case "zsh":
				_ = cmd.Root().GenZshCompletion(os.Stdout)
			case "fish":
				_ = cmd.Root().GenFishCompletion(os.Stdout, true)
			}
		},
	}

	return &cmd
}
