package config

import (
	"fmt"
	"reflect"
	"regexp"
	"strconv"
	"strings"

	"github.com/knadh/koanf/parsers/toml/v2"
	"github.com/knadh/koanf/providers/file"
	"github.com/knadh/koanf/v2"
)

type Config struct {
	Aliases        map[string][]string `koanf:"aliases" noset:"true" description:"Shortcuts for long commands"`
	Apply          ApplyConfig         `koanf:"apply" description:"Settings for 'apply' command"`
	UseColor       bool                `koanf:"color" description:"Enable colored output"`
	ConfigLocation string              `koanf:"config_location" description:"Where to look for configuration by default"`
	Enter          EnterConfig         `koanf:"enter" description:"Settings for 'enter' command"`
	Init           InitConfig          `koanf:"init" description:"Settings for 'init' command"`
	NoConfirm      bool                `koanf:"no_confirm" description:"Disable interactive confirmation input"`
	Option         OptionConfig        `koanf:"option" description:"Settings for 'option' command"`
	RootCommand    string              `koanf:"root_command" description:"Command to use to promote process to root"`
	UseNvd         bool                `koanf:"use_nvd" description:"Use 'nvd' instead of 'nix store diff-closures'"`
}

type ApplyConfig struct {
	ImplyImpureWithTag    bool   `koanf:"imply_impure_with_tag" description:"Add --impure automatically when using --tag with flakes"`
	DefaultSpecialisation string `koanf:"specialisation" description:"Name of specialisation to use by default when activating"`
	UseNom                bool   `koanf:"use_nom" description:"Use 'nix-output-monitor' as an alternative 'nix build' frontend"`
	UseGitCommitMsg       bool   `koanf:"use_git_commit_msg" description:"Use last git commit message for --tag by default"`
}

type EnterConfig struct {
	MountResolvConf bool `koanf:"mount_resolv_conf" description:"Bind-mount host 'resolv.conf' inside chroot for internet accesss"`
}

type InitConfig struct {
	EnableXserver bool              `koanf:"xserver_enabled" description:"Generate options to enable X11 display server"`
	DesktopConfig string            `koanf:"desktop_config" description:"Config options for desktop environment"`
	ExtraAttrs    map[string]string `koanf:"extra_attrs" noset:"true" description:"Extra config attrs to append to 'configuration.nix'"`
	ExtraConfig   string            `koanf:"extra_config" noset:"true" description:"Extra config string to append to 'configuration.nix'"`
}

type OptionConfig struct {
	MinScore int64 `koanf:"min_score" description:"Minimum distance score to consider an option a match"`
	Prettify bool  `koanf:"prettify" description:"Attempt to render option descriptions using Markdown"`
}

func NewConfig() *Config {
	return &Config{
		UseColor:       true,
		ConfigLocation: "/etc/nixos",
		Enter: EnterConfig{
			MountResolvConf: true,
		},
		RootCommand: "sudo",
		Option: OptionConfig{
			MinScore: 3.00,
			Prettify: true,
		},
	}
}

func ParseConfig(location string) (*Config, error) {
	k := koanf.New(".")

	if err := k.Load(file.Provider(location), toml.Parser()); err != nil {
		return nil, err
	}

	config := NewConfig()

	err := k.Unmarshal("", config)
	if err != nil {
		return nil, err
	}

	return config, nil
}

var hasWhitespaceRegex = regexp.MustCompile(`\s`)

// Validate the configuration and remove any erroneous values.
// A list of detected errors is returned, if any exist.
func (cfg *Config) Validate() ConfigErrors {
	errs := []ConfigError{}

	// First, validate the aliases. Any alias has to adhere to the following rules:
	// 1. Alias names cannot be empty.
	// 2. Alias names cannot have whitespace
	// 3. Alias names cannot start with a -
	// 4. Resolved arguments list must have a len > 1
	for alias, resolved := range cfg.Aliases {
		if len(alias) == 0 {
			errs = append(errs, ConfigError{Field: "aliases", Message: "alias name cannot be empty"})
			delete(cfg.Aliases, alias)
		} else if alias[0] == '-' {
			errs = append(errs, ConfigError{Field: fmt.Sprintf("aliases.%s", alias), Message: "alias cannot start with a '-'"})
			delete(cfg.Aliases, alias)
		} else if hasWhitespaceRegex.MatchString(alias) {
			errs = append(errs, ConfigError{Field: fmt.Sprintf("aliases.%s", alias), Message: "alias cannot have whitespace"})
			delete(cfg.Aliases, alias)
		} else if len(resolved) == 0 {
			errs = append(errs, ConfigError{Field: fmt.Sprintf("aliases.%s", alias), Message: "args list cannot be empty"})
			delete(cfg.Aliases, alias)
		}
	}

	if len(errs) > 0 {
		return errs
	}
	return nil
}

func (cfg *Config) SetValue(key string, value string) error {
	fields := strings.Split(key, ".")
	current := reflect.ValueOf(cfg).Elem()

	for i, field := range fields {
		// Find the struct field with the matching koanf tag
		found := false
		for j := 0; j < current.Type().NumField(); j++ {
			fieldInfo := current.Type().Field(j)
			if fieldInfo.Tag.Get("koanf") == field {
				current = current.Field(j)
				found = true
				break
			}
		}

		if !found {
			return ConfigError{Field: field, Message: "setting not found"}
		}

		if current.Kind() == reflect.Ptr {
			if current.IsNil() {
				current.Set(reflect.New(current.Type().Elem()))
			}
			current = current.Elem()
		}

		if i == len(fields)-1 {
			if !current.CanSet() {
				return ConfigError{Field: field, Message: "cannot change value of this setting dynamically"}
			}

			switch current.Kind() {
			case reflect.String:
				current.SetString(value)
			case reflect.Bool:
				boolVal, err := strconv.ParseBool(value)
				if err != nil {
					return ConfigError{Field: field, Message: fmt.Sprintf("invalid boolean value '%s' for field", value)}
				}
				current.SetBool(boolVal)
			case reflect.Int, reflect.Int64:
				intVal, err := strconv.ParseInt(value, 10, 64)
				if err != nil {
					return ConfigError{Field: field, Message: fmt.Sprintf("invalid integer value '%s' for field", value)}
				}
				current.SetInt(intVal)
			case reflect.Float64:
				floatVal, err := strconv.ParseFloat(value, 64)
				if err != nil {
					return ConfigError{Field: field, Message: fmt.Sprintf("invalid float value '%s' for field", value)}
				}
				current.SetFloat(floatVal)
			default:
				return ConfigError{Field: field, Message: "unsupported field type"}
			}

			return nil
		}
	}

	return nil
}

func isSettable(value *reflect.Value) bool {
	switch value.Kind() {
	case reflect.String, reflect.Bool, reflect.Int, reflect.Int64, reflect.Float64:
		return true
	}

	return false
}
