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
	Aliases        map[string][]string `koanf:"aliases"`
	Apply          *ApplyConfig        `koanf:"apply"`
	UseColor       bool                `koanf:"use_color"`
	ConfigLocation string              `koanf:"config_location"`
	Enter          *EnterConfig        `koanf:"enter"`
	Init           *InitConfig         `koanf:"init"`
	NoConfirm      bool                `koanf:"no_confirm"`
	Option         *OptionConfig       `koanf:"option"`
	UseNvd         bool                `koanf:"use_nvd"`
}

type ApplyConfig struct {
	ImplyImpureWithTag    bool   `koanf:"imply_impure_with_tag"`
	DefaultSpecialisation string `koanf:"specialisation"`
	UseNom                bool   `koanf:"use_nom"`
	UseGitCommitMsg       bool   `koanf:"use_git_commit_msg"`
}

type EnterConfig struct {
	MountResolvConf bool `koanf:"mount_resolv_conf"`
}

type InitConfig struct {
	EnableXserver bool              `koanf:"xserver_enabled"`
	DesktopConfig string            `koanf:"desktop_config"`
	ExtraAttrs    map[string]string `koanf:"extra_attrs"`
	ExtraConfig   string            `koanf:"extra_config"`
}

type OptionConfig struct {
	MaxRank  float64 `koanf:"max_rank"`
	Prettify bool    `koanf:"prettify"`
}

func ParseConfig(location string) (*Config, error) {
	k := koanf.New(".")

	if err := k.Load(file.Provider(location), toml.Parser()); err != nil {
		return nil, err
	}

	config := Config{
		ConfigLocation: "/etc/nixos",
		Enter: &EnterConfig{
			MountResolvConf: true,
		},
		Option: &OptionConfig{
			MaxRank:  3.00,
			Prettify: true,
		},
	}

	err := k.Unmarshal("", &config)
	if err != nil {
		return nil, err
	}

	return &config, nil
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

	// Then, make sure the option maximum rank makes sense.
	if cfg.Option.MaxRank < 1.00 {
		errs = append(errs, ConfigError{Field: "option.max_rank", Message: "max_rank must be at least 1.00"})
		cfg.Option.MaxRank = 3.00
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
