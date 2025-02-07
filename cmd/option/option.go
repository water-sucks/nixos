package option

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"slices"
	"strings"

	"github.com/charmbracelet/glamour"
	glamourStyles "github.com/charmbracelet/glamour/styles"
	"github.com/fatih/color"
	"github.com/sahilm/fuzzy"
	"github.com/spf13/cobra"
	"github.com/water-sucks/nixos/internal/cmd/nixopts"
	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
	"github.com/water-sucks/nixos/internal/config"
	"github.com/water-sucks/nixos/internal/configuration"
	"github.com/water-sucks/nixos/internal/logger"
	"github.com/water-sucks/nixos/internal/option"
	"github.com/water-sucks/nixos/internal/system"
)

func OptionCommand() *cobra.Command {
	opts := cmdTypes.OptionOpts{}

	cmd := cobra.Command{
		Use:   "option [flags] [NAME]",
		Short: "Query NixOS options and their details",
		Long:  "Query available NixOS module options for this system.",
		Args: func(cmd *cobra.Command, args []string) error {
			argsFunc := cobra.ExactArgs(1)
			if opts.Interactive && len(args) > 0 {
				argsFunc = cobra.MaximumNArgs(1)
			}
			if err := argsFunc(cmd, args); err != nil {
				return err
			}

			if len(args) > 0 {
				opts.OptionInput = args[0]
			}

			return nil
		},
		ValidArgsFunction: OptionsCompletionFunc(&opts),
		RunE: func(cmd *cobra.Command, args []string) error {
			return cmdUtils.CommandErrorHandler(optionMain(cmd, &opts))
		},
	}

	cmd.Flags().BoolVarP(&opts.DisplayJson, "json", "j", false, "Output information in JSON format")
	cmd.Flags().BoolVarP(&opts.Interactive, "interactive", "i", false, "Show interactive search TUI for options")
	cmd.Flags().BoolVarP(&opts.NoUseCache, "no-cache", "n", false, "Do not attempt to use prebuilt option cache")
	cmd.Flags().Int64VarP(&opts.MinScore, "min-score", "s", 0, "")
	cmd.Flags().BoolVarP(&opts.DisplayValueOnly, "value-only", "v", false, "Show only the selected option's value")

	nixopts.AddIncludesNixOption(&cmd, &opts.NixPathIncludes)

	cmd.MarkFlagsMutuallyExclusive("json", "interactive", "value-only")

	cmdUtils.SetHelpFlagText(&cmd)
	cmd.SetHelpTemplate(cmd.HelpTemplate() + `
Arguments:
  [NAME]  Name of option to use. Not required in interactive mode.
`)

	return &cmd
}

func optionMain(cmd *cobra.Command, opts *cmdTypes.OptionOpts) error {
	log := logger.FromContext(cmd.Context())
	cfg := config.FromContext(cmd.Context())
	s := system.NewLocalSystem()

	minScore := cfg.Option.MinScore
	if cmd.Flags().Changed("min-score") {
		minScore = opts.MinScore
	}

	if !s.IsNixOS() {
		msg := "this command is only supported on NixOS systems"
		log.Error(msg)
		return fmt.Errorf("%v", msg)
	}

	nixosConfig, err := configuration.FindConfiguration(log, cfg, opts.NixPathIncludes, false)
	if err != nil {
		log.Errorf("failed to find configuration: %v", err)
		return err
	}

	useCache := !opts.NoUseCache
	if useCache {
		_, err := os.Stat(prebuiltOptionCachePath)
		if err != nil {
			log.Warnf("error accessing prebuilt option cache: %v", err)
			useCache = false
		}
	}

	optionsFile := prebuiltOptionCachePath
	if !useCache {
		log.Info("building options list")
		f, err := buildOptionCache(s, nixosConfig)
		if err != nil {
			log.Errorf("failed to build option list: %v", err)
			return err
		}
		optionsFile = f
	}

	options, err := option.LoadOptionsFromFile(optionsFile)
	if err != nil {
		log.Errorf("failed to load options: %v", err)
		return err
	}

	if opts.Interactive {
		log.Info("interactive search not implemented yet, coming soon")
		return nil
	}

	exactOptionMatchIdx := slices.IndexFunc(options, func(o option.NixosOption) bool {
		return o.Name == opts.OptionInput
	})
	if exactOptionMatchIdx != -1 {
		o := options[exactOptionMatchIdx]

		evaluatedValue := evaluateOptionValue(s, nixosConfig, o.Name)

		if opts.DisplayJson {
			displayOptionJson(&o)
		} else if opts.DisplayValueOnly {
			if evaluatedValue.ErrorMessage != "" {
				log.Errorf("failed to evaluate value, trace received while evaluating:\n\n%v", evaluatedValue.ErrorMessage)
				return fmt.Errorf("%v", evaluatedValue.ErrorMessage)
			} else {
				fmt.Printf("%v\n", evaluatedValue.Value)
			}
		} else {
			prettyPrintOption(&o, evaluatedValue, cfg.Option.Prettify)
		}

		return nil
	}

	msg := fmt.Sprintf("no exact match for query '%s' found", opts.OptionInput)
	err = fmt.Errorf("%v", msg)

	fuzzySearchResults := fuzzy.FindFrom(opts.OptionInput, options)
	if len(fuzzySearchResults) > 10 {
		fuzzySearchResults = fuzzySearchResults[:10]
	}

	fuzzySearchResults = filterMinimumScoreMatches(fuzzySearchResults, int(minScore))

	if opts.DisplayJson {
		displayErrorJson(msg, fuzzySearchResults)
		return err
	}

	log.Error(msg)
	if len(fuzzySearchResults) > 0 {
		log.Print("\nSome similar options were found:\n")
		for _, v := range fuzzySearchResults {
			log.Printf(" - %s\n", v.Str)
		}
	} else {
		log.Print("\nTry refining your search query.\n")
	}

	return err
}

func displayOptionJson(o *option.NixosOption) {
	type optionJson struct {
		Name         string   `json:"name"`
		Description  string   `json:"description"`
		Type         string   `json:"type"`
		Default      string   `json:"default"`
		Example      string   `json:"example"`
		Location     []string `json:"loc"`
		ReadOnly     bool     `json:"readOnly"`
		Declarations []string `json:"declarations"`
	}

	defaultText := ""
	if o.Default != nil {
		defaultText = o.Default.Text
	}

	exampleText := ""
	if o.Example != nil {
		exampleText = o.Example.Text
	}

	bytes, _ := json.MarshalIndent(optionJson{
		Name:         o.Name,
		Description:  o.Description,
		Type:         o.Type,
		Default:      defaultText,
		Example:      exampleText,
		Location:     o.Location,
		ReadOnly:     o.ReadOnly,
		Declarations: o.Declarations,
	}, "", "  ")
	fmt.Printf("%v\n", string(bytes))
}

func displayErrorJson(msg string, matches fuzzy.Matches) {
	type errorJson struct {
		Message        string   `json:"message"`
		SimilarOptions []string `json:"similar_options"`
	}

	matchedStrings := make([]string, len(matches))
	for i, match := range matches {
		matchedStrings[i] = match.Str
	}

	bytes, _ := json.MarshalIndent(errorJson{
		Message:        msg,
		SimilarOptions: matchedStrings,
	}, "", "  ")
	fmt.Printf("%v\n", string(bytes))
}

var (
	titleStyle  = color.New(color.Bold)
	italicStyle = color.New(color.Italic)
)

func prettyPrintOption(o *option.NixosOption, evaluatedValue *evaluatedOptionValue, pretty bool) {
	_ = pretty

	r := markdownRenderer()
	desc := strings.TrimSpace(stripInlineCodeAnnotations(o.Description))
	if desc == "" {
		desc = italicStyle.Sprint("(none)")
	} else {
		d, err := r.Render(desc)
		if err != nil {
			desc = italicStyle.Sprintf("failed to render description: %v", err)
		} else {
			desc = strings.TrimSpace(d)
		}
	}

	valueText := ""
	if evaluatedValue.ErrorMessage != "" {
		valueText = color.RedString("failed to evaluate value: %v", evaluatedValue.ErrorMessage)
	} else {
		valueText = color.WhiteString(strings.TrimSpace(evaluatedValue.Value))
	}

	var defaultText string
	if o.Default != nil {
		defaultText = color.WhiteString(strings.TrimSpace(o.Default.Text))
	} else {
		defaultText = italicStyle.Sprint("(none)")
	}

	exampleText := ""
	if o.Example != nil {
		exampleText = color.WhiteString(strings.TrimSpace(o.Example.Text))
	}

	fmt.Printf("%v\n%v\n\n", titleStyle.Sprint("Name"), o.Name)
	fmt.Printf("%v\n%v\n\n", titleStyle.Sprint("Description"), desc)
	fmt.Printf("%v\n%v\n\n", titleStyle.Sprint("Type"), italicStyle.Sprint(o.Type))

	fmt.Printf("%v\n%v\n\n", titleStyle.Sprint("Value"), valueText)
	fmt.Printf("%v\n%v\n\n", titleStyle.Sprint("Default"), defaultText)
	if exampleText != "" {
		fmt.Printf("%v\n%v\n\n", titleStyle.Sprint("Example"), exampleText)
	}

	if len(o.Declarations) > 0 {
		fmt.Printf("%v\n", titleStyle.Sprint("Declared In"))
		for _, v := range o.Declarations {
			fmt.Printf("  - %v\n", italicStyle.Sprint(v))
		}
	}
	if o.ReadOnly {
		fmt.Printf("\n%v\n", color.YellowString("This option is read-only."))
	}
}

var markdownRenderIndentWidth uint = 0

func markdownRenderer() *glamour.TermRenderer {
	glamourStyles.DarkStyleConfig.Document.Margin = &markdownRenderIndentWidth

	r, _ := glamour.NewTermRenderer(
		glamour.WithStyles(glamourStyles.DarkStyleConfig),
		glamour.WithWordWrap(80),
	)

	return r
}

var annotationsToRemove = []string{
	"{option}`",
	"{var}`",
	"{file}`",
	"{env}`",
	"{command}`",
	"{manpage}`",
}

func stripInlineCodeAnnotations(slice string) string {
	result := slice

	for _, input := range annotationsToRemove {
		result = strings.ReplaceAll(result, input, "`")
	}

	return result
}

type evaluatedOptionValue struct {
	Value        string
	ErrorMessage string
}

func evaluateOptionValue(s system.CommandRunner, cfg configuration.Configuration, name string) *evaluatedOptionValue {
	var argv []string

	switch c := cfg.(type) {
	case *configuration.FlakeRef:
		attr := fmt.Sprintf("%s#nixosConfigurations.%s.config.%s", c.URI, c.System, name)
		argv = []string{"nix", "eval", attr}
	case *configuration.LegacyConfiguration:
		attr := fmt.Sprintf("config.%s", name)
		argv = []string{"nix-instantiate", "--eval", "<nixpkgs/nixos>", "-A", attr}
		for _, v := range c.Includes {
			argv = append(argv, "-I", v)
		}
	}

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	cmd := system.NewCommand(argv[0], argv[1:]...)
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	_, _ = s.Run(cmd)
	return &evaluatedOptionValue{
		Value:        strings.TrimSpace(stdout.String()),
		ErrorMessage: strings.TrimSpace(stderr.String()),
	}
}

// Filter a sorted (descending) match list until a minimum score is reached.
// Return a slice of the original matches.
func filterMinimumScoreMatches(matches []fuzzy.Match, minScore int) []fuzzy.Match {
	for i, v := range matches {
		if v.Score < minScore {
			return matches[:i]
		}
	}

	return matches
}
