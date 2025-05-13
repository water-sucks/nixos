package manual

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/spf13/cobra"
	"github.com/nix-community/nixos-cli/internal/cmd/utils"
	"github.com/nix-community/nixos-cli/internal/constants"
	"github.com/nix-community/nixos-cli/internal/logger"
	"github.com/nix-community/nixos-cli/internal/system"
)

func ManualCommand() *cobra.Command {
	cmd := cobra.Command{
		Use:   "manual",
		Short: "Open the NixOS manual",
		Long:  "Open the NixOS manual in a browser.",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return cmdUtils.CommandErrorHandler(manualMain(cmd))
		},
	}

	cmdUtils.SetHelpFlagText(&cmd)

	return &cmd
}

const (
	localManualFile = constants.CurrentSystem + "/sw/share/doc/nixos/index.html"
	manualURL       = "https://nixos.org/manual/nixos/stable"
)

func manualMain(cmd *cobra.Command) error {
	log := logger.FromContext(cmd.Context())
	s := system.NewLocalSystem(log)

	if !s.IsNixOS() {
		log.Error("this command is only supported on NixOS systems")
		return nil
	}

	url := localManualFile
	if _, err := os.Stat(url); err != nil {
		log.Error("local documentation is not available, opening manual for current NixOS stable version")
		url = manualURL
	}

	var openCommand string

	browsers := strings.Split(os.Getenv("BROWSERS"), ":")
	for _, browser := range browsers {
		if p, err := exec.LookPath(browser); err == nil && p != "" {
			openCommand = p
			break
		}
	}

	defaultCommands := []string{"xdg-open", "w3m", "open"}
	if openCommand == "" {
		for _, cmd := range defaultCommands {
			if p, err := exec.LookPath(cmd); err == nil && p != "" {
				openCommand = p
				break
			}
		}

		if openCommand == "" {
			msg := "unable to locate suitable browser to open manual, exiting"
			log.Error(msg)
			return fmt.Errorf("%v", msg)
		}
	}

	log.Infof("opening manual using %v", openCommand)
	err := exec.Command(openCommand, url).Run()
	if err != nil {
		log.Errorf("failed to open manual: %v", err)
		return err
	}

	return nil
}
