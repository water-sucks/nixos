package types

import "github.com/spf13/cobra"

type CompletionFunc func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective)
