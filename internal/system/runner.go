package system

import "os"

type CommandRunner interface {
	Run(cmd *Command) (int, error)
}

type Command struct {
	Name   string
	Args   []string
	Stdin  *os.File
	Stdout *os.File
	Stderr *os.File
	Env    map[string]string
}

func NewCommand(name string, args ...string) *Command {
	return &Command{
		Name:   name,
		Args:   args,
		Stdin:  os.Stdin,
		Stdout: os.Stdout,
		Stderr: os.Stderr,
		Env:    make(map[string]string),
	}
}

func (c *Command) SetEnv(key string, value string) {
	c.Env[key] = value
}
