package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strings"

	"github.com/spf13/cobra"
	"github.com/water-sucks/nixos/internal/settings"
)

func main() {
	// Attempt to find the root of the Git repository. This is where
	// documentation generation will start from
	cmd := exec.Command("git", "rev-parse", "--show-toplevel")
	rootDir, err := cmd.Output()
	if err != nil {
		fmt.Printf("error: couldn't find repository root directory: %v\n", err)
		os.Exit(1)
	}

	docsPath := filepath.Join(strings.TrimSpace(string(rootDir)), "doc")
	err = os.Chdir(docsPath)
	if err != nil {
		fmt.Printf("error: couldn't change working directory to %v: %v\n", docsPath, err)
		os.Exit(1)
	}

	rootCmd := &cobra.Command{
		Use: "build",
		CompletionOptions: cobra.CompletionOptions{
			DisableDefaultCmd: true,
			HiddenDefaultCmd:  true,
		},
	}

	rootCmd.AddCommand(&cobra.Command{
		Use:   "site",
		Short: "Generate Markdown documentation for settings and modules",
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Println("generating settings documentation")

			generatedSettingsPath := filepath.Join("src", "generated-settings.md")
			if err := generateSettingsDoc(generatedSettingsPath, *settings.NewSettings()); err != nil {
				return err
			}

			fmt.Println("generating module documentation")

			generatedModulePath := filepath.Join("src", "generated-module.md")
			if err := generateModuleDoc(generatedModulePath); err != nil {
				return err
			}

			fmt.Println("generated settings and modules for mdbook site")

			return nil
		},
	})

	rootCmd.AddCommand(&cobra.Command{
		Use:   "man",
		Short: "Generate man pages using lowdown",
		RunE: func(cmd *cobra.Command, args []string) error {
			return nil
		},
	})

	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func generateSettingsDoc(filename string, defaults settings.Settings) error {
	var sb strings.Builder

	writeSettingsDoc(reflect.TypeOf(defaults), reflect.ValueOf(defaults), "", &sb, 2)

	return os.WriteFile(filename, []byte(sb.String()), 0o644)
}

func generateModuleDoc(filename string) error {
	var sb strings.Builder

	// Set cwd to parent directory to match expected module root
	cwd, _ := os.Getwd()
	cmd := exec.Command("nix-options-doc", "--strip-prefix")
	cmd.Dir = filepath.Dir(cwd)
	cmd.Stdout = &sb

	if err := cmd.Run(); err != nil {
		fmt.Printf("error: couldn't generate docs for module with nix-options-doc: %v\n", err)
		return err
	}

	// Strip the first line and some whitespace (assumed to be the title)
	lines := strings.Split(sb.String(), "\n")
	if len(lines) == 0 {
		return fmt.Errorf("no output from nix-options-doc")
	}
	lines = lines[3:]

	gitCmd := exec.Command("git", "rev-parse", "HEAD")
	gitCmd.Dir = filepath.Dir(cwd)
	var gitOut bytes.Buffer
	gitCmd.Stdout = &gitOut
	if err := gitCmd.Run(); err != nil {
		fmt.Printf("error: couldn't get Git commit: %v\n", err)
		return err
	}
	commit := strings.TrimSpace(gitOut.String())

	repoBaseURL := fmt.Sprintf("https://github.com/water-sucks/nixos/blob/%s", commit)

	// Regex to match Markdown header links: ## [`something`](module.nix#L123)
	re := regexp.MustCompile(`(?m)^## \[` +
		`(?P<name>.*?)` +
		`\]\(` +
		`(?P<file>[^)]+)` +
		`\)`)

	for i, line := range lines {
		lines[i] = re.ReplaceAllString(line, fmt.Sprintf("## [`${name}`](%s/${file})", repoBaseURL))
	}

	final := strings.Join(lines, "\n")
	return os.WriteFile(filename, []byte(final), 0o644)
}

func writeSettingsDoc(t reflect.Type, v reflect.Value, path string, sb *strings.Builder, depth int) {
	type nestedField struct {
		field    reflect.StructField
		fieldVal reflect.Value
		fullKey  string
	}

	var generalItems []string
	var nestedFields []nestedField

	for i := range t.NumField() {
		field := t.Field(i)
		tag := field.Tag

		koanfKey := tag.Get("koanf")
		if koanfKey == "" {
			continue
		}

		fullKey := path + koanfKey
		fieldVal := v.Field(i)

		if field.Type.Kind() == reflect.Struct {
			nestedFields = append(nestedFields, nestedField{field, fieldVal, fullKey})
		} else {
			defaultVal := formatValue(fieldVal)
			descriptions := settings.SettingsDocs[fullKey]
			desc := descriptions.Long
			if desc == "" {
				desc = descriptions.Short
			}

			generalItems = append(generalItems, fmt.Sprintf("- **`%s`**\n\n  %s\n\n  **Default**: %s\n", fullKey, desc, defaultVal))
		}
	}

	if len(generalItems) > 0 {
		if path == "" {
			sb.WriteString("## General\n\n")
		}
		sort.Strings(generalItems)
		for _, line := range generalItems {
			sb.WriteString(line + "\n")
		}
		sb.WriteString("\n")
	}

	// Then print subsections
	for _, entry := range nestedFields {
		descriptions := settings.SettingsDocs[entry.fullKey]
		desc := descriptions.Long
		if desc == "" {
			desc = descriptions.Short
		}

		fmt.Fprintf(sb, "%s `%s`\n\n%s\n\n", strings.Repeat("#", depth), entry.fullKey, desc)
		writeSettingsDoc(entry.field.Type, entry.fieldVal, entry.fullKey+".", sb, depth+1)
	}
}

// formatValue formats a default value for documentation output.
func formatValue(v reflect.Value) string {
	if !v.IsValid() {
		return "n/a"
	}
	switch v.Kind() {
	case reflect.String:
		if v.String() == "" {
			return `""`
		}
		return fmt.Sprintf("`%s`", v.String())
	case reflect.Bool:
		return fmt.Sprintf("`%t`", v.Bool())
	case reflect.Int, reflect.Int64:
		return fmt.Sprintf("`%d`", v.Int())
	case reflect.Map, reflect.Slice:
		if v.Len() == 0 {
			return "`[]`"
		}
		return "`(multiple entries)`"
	default:
		return fmt.Sprintf("`%v`", v.Interface())
	}
}
