package root

import (
	"fmt"
	"os"
	"os/exec"

	"github.com/nix-community/nixos-cli/internal/utils"
	"github.com/spf13/cobra"
)

func addAliasCmd(parent *cobra.Command, alias string, args []string) error {
	displayedArgs := utils.EscapeAndJoinArgs(args)
	description := fmt.Sprintf("Alias for `%v`.", displayedArgs)

	existingCommands := parent.Commands()
	for _, v := range existingCommands {
		if v.Name() == alias {
			return fmt.Errorf("alias conflicts with existing builtin command")
		}
	}

	if !parent.ContainsGroup("aliases") {
		parent.AddGroup(&cobra.Group{
			ID:    "aliases",
			Title: "Aliases",
		})
	}

	cmd := &cobra.Command{
		Use:                alias,
		Short:              description,
		Long:               description,
		GroupID:            "aliases",
		DisableFlagParsing: true,
		RunE: func(cmd *cobra.Command, passedArgs []string) error {
			fullArgsList := append(args, passedArgs...)

			root := cmd.Root()
			root.SetArgs(fullArgsList)
			return root.Execute()
		},
		ValidArgsFunction: func(cmd *cobra.Command, passedArgs []string, toComplete string) ([]string, cobra.ShellCompDirective) {
			// HACK: So this is a rather lazy way of implementing completion for aliases.
			// I couldn't figure out how to get completions from the flag, so I decided
			// to just run the hidden completion command with the resolved arguments
			// and anything else that was passed. This should be negligible from a
			// performance perspective, but it's definitely a piece of shit.
			// Also, if you know, you know.

			// evil completion command hacking
			completionArgv := []string{os.Args[0], "__complete"} // what the fuck?
			completionArgv = append(completionArgv, args...)
			completionArgv = append(completionArgv, passedArgs...)
			completionArgv = append(completionArgv, toComplete)

			completionCmd := exec.Command(completionArgv[0], completionArgv[1:]...)
			completionCmd.Stdout = os.Stdout
			completionCmd.Stderr = os.Stderr

			// The completion command should always run.
			if err := completionCmd.Run(); err != nil {
				cobra.CompDebugln("failed to run completion command: "+err.Error(), true)
				os.Exit(1)
			}

			os.Exit(0)

			return []string{}, cobra.ShellCompDirectiveNoFileComp
		},
	}

	parent.AddCommand(cmd)

	return nil
}
