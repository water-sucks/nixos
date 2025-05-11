package generation

import (
	"fmt"
	"os"
	"regexp"
	"slices"
	"sort"
	"strconv"

	"github.com/spf13/cobra"
	"github.com/water-sucks/nixos/internal/cmd/opts"
	"github.com/water-sucks/nixos/internal/constants"
	"github.com/water-sucks/nixos/internal/logger"
)

var genLinkRegex = regexp.MustCompile(`-(\d+)-link$`)

func CompleteProfileFlag(_ *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
	profiles := []string{"system"}

	entries, err := os.ReadDir(constants.NixSystemProfileDirectory)
	if err != nil {
		return []string{}, cobra.ShellCompDirectiveNoFileComp
	}

	for _, v := range entries {
		name := v.Name()

		if matches := genLinkRegex.FindStringSubmatch(name); len(matches) > 0 {
			continue
		}

		profiles = append(profiles, name)
	}

	sort.Strings(profiles)

	return profiles, cobra.ShellCompDirectiveNoFileComp
}

func CompleteGenerationNumber(profile *string, limit int) cmdOpts.CompletionFunc {
	return func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		log := logger.FromContext(cmd.Context())

		if limit != 0 && len(args) >= limit {
			return []string{}, cobra.ShellCompDirectiveNoFileComp
		}

		generations, err := CollectGenerationsInProfile(log, *profile)
		if err != nil {
			return []string{}, cobra.ShellCompDirectiveNoFileComp
		}

		exclude := []uint64{}
		for _, v := range args {
			parsed, err := strconv.ParseUint(v, 10, 64)
			if err != nil {
				continue
			}
			exclude = append(exclude, parsed)
		}

		genNumbers := []string{}
		for _, v := range generations {
			if slices.Contains(exclude, v.Number) {
				continue
			}
			genNumber := fmt.Sprint(v.Number)
			if v.Description != "" {
				genNumber += "\t" + v.Description
			}
			genNumbers = append(genNumbers, genNumber)
		}

		sort.Strings(genNumbers)

		return genNumbers, cobra.ShellCompDirectiveNoFileComp
	}
}

func CompleteGenerationNumberFlag(profile *string) cmdOpts.CompletionFunc {
	return func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		log := logger.FromContext(cmd.Context())

		generations, err := CollectGenerationsInProfile(log, *profile)
		if err != nil {
			return []string{}, cobra.ShellCompDirectiveNoFileComp
		}

		genNumbers := []string{}
		for _, v := range generations {
			genNumber := fmt.Sprint(v.Number)
			if v.Description != "" {
				genNumber += "\t" + v.Description
			}
			genNumbers = append(genNumbers, genNumber)
		}

		sort.Strings(genNumbers)

		return genNumbers, cobra.ShellCompDirectiveNoFileComp
	}
}
