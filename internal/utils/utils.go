package utils

import (
	"os"
	"os/exec"
	"syscall"

	"github.com/water-sucks/nixos/internal/logger"
)

// Re-exec the current process as root with the same arguments.
// This is done with the provided rootCommand parameter, which
// usually is "sudo" or "doas", and comes from the command config.
func ExecAsRoot(log *logger.Logger, rootCommand string) error {
	rootCommandPath, err := exec.LookPath(rootCommand)
	if err != nil {
		return err
	}

	argv := []string{rootCommand}
	argv = append(argv, os.Args...)

	err = syscall.Exec(rootCommandPath, argv, os.Environ())
	return err
}
