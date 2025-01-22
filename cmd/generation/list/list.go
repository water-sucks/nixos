package list

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/olekukonko/tablewriter"
	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
	"github.com/water-sucks/nixos/internal/generation"
	"github.com/water-sucks/nixos/internal/logger"
)

func GenerationListCommand(genOpts *cmdTypes.GenerationOpts) *cobra.Command {
	opts := cmdTypes.GenerationListOpts{}

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

func loadGenerations(log *logger.Logger, profileName string) ([]generation.Generation, error) {
	generations, err := generation.CollectGenerationsInProfile(log, profileName)
	if err != nil {
		switch v := err.(type) {
		case *generation.GenerationReadError:
			for _, err := range v.Errors {
				log.Warnf("%v", err)
			}

		default:
			log.Errorf("error collecting generation information: %v", v)
			return nil, v
		}
	}

	return generations, nil
}

func generationListMain(cmd *cobra.Command, genOpts *cmdTypes.GenerationOpts, opts *cmdTypes.GenerationListOpts) error {
	log := logger.FromContext(cmd.Context())

	generations, err := loadGenerations(log, genOpts.ProfileName)
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

	err = generationUI(generations)
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
