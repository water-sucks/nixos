package cmd

import (
	"context"
	"fmt"
	"strings"

	"github.com/urfave/cli/v3"
)

func CommandNotFound(ctx context.Context, cmd *cli.Command, s string) {
	fmt.Fprintf(cmd.Root().ErrWriter, "error: unknown subcommand '%v'\n\n", s)

	// TODO: add custom suggestions here

	fmt.Fprintln(cmd.Root().ErrWriter, "For more information, add --help.")
}

func OnUsageError(ctx context.Context, cmd *cli.Command, err error, isSubcommand bool) error {
	// This is a hacky way of showing the right error that I want, but
	// it should change in the future, hopefully.
	msg := err.Error()
	if strings.HasPrefix(msg, "flag provided but not defined") {
		words := strings.Split(msg, " ")
		flag := words[len(words)-1]
		fmt.Fprintf(cmd.Root().ErrWriter, "error: unrecognised flag '%v'\n", flag)
	} else {
		fmt.Fprintf(cmd.Root().ErrWriter, "error: %v\n", msg)
	}

	fmt.Fprintln(cmd.Root().ErrWriter, "\nFor more information, add --help.")

	// TODO: add custom suggestions here

	return err
}
