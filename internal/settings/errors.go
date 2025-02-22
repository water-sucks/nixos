package settings

import "fmt"

type SettingsErrors []SettingsError

type SettingsError struct {
	Field   string
	Message string
}

func (e SettingsError) Error() string {
	return fmt.Sprintf("%s: %s", e.Field, e.Message)
}
