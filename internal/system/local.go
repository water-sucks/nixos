package system

import (
	"os"
	"os/exec"
)

type LocalSystem struct{}

func NewLocalSystem() *LocalSystem {
	return &LocalSystem{}
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
