package option

import (
	"os"
	"strings"

	"github.com/nix-community/nixos-cli/internal/cmd/opts"
	"github.com/nix-community/nixos-cli/internal/configuration"
	"github.com/nix-community/nixos-cli/internal/logger"
	"github.com/nix-community/nixos-cli/internal/option"
	"github.com/nix-community/nixos-cli/internal/settings"
	"github.com/nix-community/nixos-cli/internal/system"
	"github.com/spf13/cobra"
)

func loadOptions(log *logger.Logger, cfg *settings.Settings, includes []string) (option.NixosOptionSource, error) {
	s := system.NewLocalSystem(log)

	nixosConfig, err := configuration.FindConfiguration(log, cfg, includes, false)
	if err != nil {
		log.Errorf("failed to find configuration: %v", err)
		return nil, err
	}

	// Always use cache for completion if available.
	useCache := true
	_, err = os.Stat(prebuiltOptionCachePath)
	if err != nil {
		log.Warnf("error accessing prebuilt option cache: %v", err)
		useCache = false
	}

	optionsFile := prebuiltOptionCachePath
	if !useCache {
		log.Info("building options list")
		f, err := buildOptionCache(s, nixosConfig)
		if err != nil {
			log.Errorf("failed to build option list: %v", err)
			return nil, err
		}
		optionsFile = f
	}

	options, err := option.LoadOptionsFromFile(optionsFile)
	if err != nil {
		log.Errorf("failed to load options: %v", err)
		return nil, err
	}

	return options, nil
}

func OptionsCompletionFunc(opts *cmdOpts.OptionOpts) cmdOpts.CompletionFunc {
	return func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		log := logger.FromContext(cmd.Context())
		cfg := settings.FromContext(cmd.Context())

		if len(args) != 0 {
			return []string{}, cobra.ShellCompDirectiveNoFileComp
		}

		options, err := loadOptions(log, cfg, opts.NixPathIncludes)
		if err != nil {
			return []string{}, cobra.ShellCompDirectiveNoFileComp
		}

		completions := []string{}
		for _, v := range options {
			if toComplete == v.Name {
				return []string{v.Name}, cobra.ShellCompDirectiveNoFileComp
			}

			if strings.HasPrefix(v.Name, toComplete) {
				completions = append(completions, v.Name)
			}
		}

		return completions, cobra.ShellCompDirectiveNoSpace | cobra.ShellCompDirectiveNoFileComp
	}
}
