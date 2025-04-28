package system

import (
	"os"
	"os/exec"

	"github.com/water-sucks/nixos/internal/logger"
)

type LocalSystem struct {
	logger *logger.Logger
}

func NewLocalSystem(logger *logger.Logger) *LocalSystem {
	return &LocalSystem{
		logger: logger,
	}
}

func (l *LocalSystem) Run(cmd *Command) (int, error) {
	command := exec.Command(cmd.Name, cmd.Args...)

	command.Stdout = cmd.Stdout
	command.Stderr = cmd.Stderr
	command.Stdin = cmd.Stdin
	command.Env = os.Environ()

	for key, value := range cmd.Env {
		command.Env = append(command.Env, key+"="+value)
	}

	err := command.Run()

	if exitErr, ok := err.(*exec.ExitError); ok {
		if status, ok := exitErr.Sys().(interface{ ExitStatus() int }); ok {
			return status.ExitStatus(), err
		}
	}

	if err == nil {
		return 0, nil
	}

	return 0, err
}

func (l *LocalSystem) IsNixOS() bool {
	_, err := os.Stat("/etc/NIXOS")
	return err == nil
}

func (l *LocalSystem) Logger() *logger.Logger {
	return l.logger
}
