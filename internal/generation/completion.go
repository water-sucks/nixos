package generation

import (
	"os"
	"regexp"

	"github.com/spf13/cobra"
	"github.com/water-sucks/nixos/internal/constants"
)

var genLinkRegex = regexp.MustCompile(`-(\d+)-link$`)

func CompleteProfileFlag(_ *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
	profiles := []string{"system"}

	entries, err := os.ReadDir(constants.NixSystemProfileDirectory)
	if err != nil {
		return []string{}, cobra.ShellCompDirectiveDefault
	}

	for _, v := range entries {
		name := v.Name()

		if matches := genLinkRegex.FindStringSubmatch(name); len(matches) > 0 {
			continue
		}

		profiles = append(profiles, name)
	}

	return profiles, cobra.ShellCompDirectiveDefault
}
