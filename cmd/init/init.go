package cmd

import (
	"encoding/json"

	"github.com/spf13/cobra"
	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
	"github.com/water-sucks/nixos/internal/logger"
)

func InitCommand() *cobra.Command {
	opts := cmdTypes.InitOpts{}

	cmd := cobra.Command{
		Use:   "init",
		Short: "Initialize a NixOS configuration",
		Long:  "Initialize a NixOS configuration template and/or hardware options.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return initMain(cmd, &opts)
		},
	}

	cmdUtils.SetHelpFlagText(&cmd)

	cmd.Flags().StringVarP(&opts.Directory, "dir", "d", "/etc/nixos", "Directory `path` in root to write to")
	cmd.Flags().BoolVarP(&opts.ForceWrite, "force", "f", false, "Force generation of all configuration files")
	cmd.Flags().BoolVarP(&opts.ForceWrite, "no-fs", "n", false, "Do not generate 'fileSystem' options configuration")
	cmd.Flags().StringVarP(&opts.Root, "root", "r", "/", "Treat `path` as the root directory")
	cmd.Flags().BoolVarP(&opts.ShowHardwareConfig, "show-hardware-config", "s", false, "Print hardware config to stdout and exit")

	return &cmd
}

func initMain(cmd *cobra.Command, opts *cmdTypes.InitOpts) error {
	log := logger.FromContext(cmd.Context())

	bytes, _ := json.MarshalIndent(opts, "", "  ")
	log.Infof("init: %v\n", string(bytes))

	return nil
}
