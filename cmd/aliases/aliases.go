package cmd

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/spf13/cobra"

	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
	"github.com/water-sucks/nixos/internal/config"
)

func AliasCommand() *cobra.Command {
	opts := cmdTypes.AliasesOpts{}

	cmd := cobra.Command{
		Use:   "aliases",
		Short: "List configured aliases",
		Long:  "List configured aliases and what commands they resolve to.",
		Run: func(cmd *cobra.Command, args []string) {
			aliasesMain(cmd, &opts)
		},
	}

	cmd.Flags().BoolVarP(&opts.DisplayJson, "json", "j", false, "Output information in JSON format")

	cmdUtils.SetHelpFlagText(&cmd)

	return &cmd
}

func aliasesMain(cmd *cobra.Command, opts *cmdTypes.AliasesOpts) {
	cfg := config.FromContext(cmd.Context())
	aliases := cfg.Aliases

	if opts.DisplayJson {
		bytes, _ := json.MarshalIndent(aliases, "", "  ")
		fmt.Println(string(bytes))
		return
	}

	maxColumnLength := 0
	for alias := range aliases {
		length := len(alias)
		if length > maxColumnLength {
			maxColumnLength = length
		}
	}

	for alias, resolved := range aliases {
		fmt.Printf("%-*s :: %s\n", maxColumnLength, alias, escapeAndJoinArgs(resolved))
	}
}

func escapeAndJoinArgs(args []string) string {
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
