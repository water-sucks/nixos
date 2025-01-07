package config

import "fmt"

type ConfigErrors []ConfigError

type ConfigError struct {
	Field   string
	Message string
}

func (e ConfigError) Error() string {
	return fmt.Sprintf("%s: %s", e.Field, e.Message)
}
