package list

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/olekukonko/tablewriter"
	"github.com/nix-community/nixos-cli/cmd/generation/shared"
	"github.com/nix-community/nixos-cli/internal/cmd/opts"
	"github.com/nix-community/nixos-cli/internal/cmd/utils"
	"github.com/nix-community/nixos-cli/internal/generation"
	"github.com/nix-community/nixos-cli/internal/logger"
)

func GenerationListCommand(genOpts *cmdOpts.GenerationOpts) *cobra.Command {
	opts := cmdOpts.GenerationListOpts{}

	cmd := cobra.Command{
		Use:   "list",
		Short: "List all NixOS generations in a profile",
		Long:  "List all generations in a NixOS profile and their details.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return cmdUtils.CommandErrorHandler(generationListMain(cmd, genOpts, &opts))
		},
	}

	cmd.Flags().BoolVarP(&opts.DisplayJson, "json", "j", false, "Display in JSON format")
	cmd.Flags().BoolVarP(&opts.DisplayTable, "table", "t", false, "Display in table format")

	cmdUtils.SetHelpFlagText(&cmd)

	return &cmd
}

func generationListMain(cmd *cobra.Command, genOpts *cmdOpts.GenerationOpts, opts *cmdOpts.GenerationListOpts) error {
	log := logger.FromContext(cmd.Context())

	generations, err := genUtils.LoadGenerations(log, genOpts.ProfileName, true)
	if err != nil {
		return err
	}

	if opts.DisplayTable {
		displayTable(generations)
		return nil
	}

	if opts.DisplayJson {
		bytes, _ := json.MarshalIndent(generations, "", "  ")
		fmt.Printf("%v\n", string(bytes))

		return nil
	}

	err = generationUI(log, genOpts.ProfileName, generations)
	if err != nil {
		log.Errorf("error running generation TUI: %v", err)
		return err
	}

	return nil
}

func displayTable(generations []generation.Generation) {
	data := make([][]string, len(generations))

	for i, v := range generations {
		data[i] = []string{
			fmt.Sprintf("%v", v.Number),
			fmt.Sprintf("%v", v.IsCurrent),
			fmt.Sprintf("%v", v.CreationDate.Format(time.ANSIC)),
			v.NixosVersion,
			v.NixpkgsRevision,
			v.ConfigurationRevision,
			v.KernelVersion,
			strings.Join(v.Specialisations, ","),
		}
	}

	table := tablewriter.NewWriter(os.Stdout)
	table.SetHeader([]string{"Number", "Current", "Date", "NixOS Version", "Nixpkgs Version", "Config Version", "Kernel Version", "Specialisations"})
	table.SetAutoWrapText(false)
	table.SetAutoFormatHeaders(true)
	table.SetHeaderAlignment(tablewriter.ALIGN_LEFT)
	table.SetAlignment(tablewriter.ALIGN_LEFT)
	table.SetCenterSeparator("")
	table.SetColumnSeparator("")
	table.SetRowSeparator("")
	table.SetHeaderLine(false)
	table.SetBorder(false)
	table.SetTablePadding("\t")
	table.SetNoWhiteSpace(true)
	table.AppendBulk(data)
	table.Render()
}
