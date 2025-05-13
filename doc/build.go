package main

import (
	"bytes"
	_ "embed"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strings"

	"github.com/nix-community/nixos-cli/internal/settings"
	"github.com/spf13/cobra"
)

func main() {
	rootCmd := &cobra.Command{
		Use: "build",
		CompletionOptions: cobra.CompletionOptions{
			DisableDefaultCmd: true,
			HiddenDefaultCmd:  true,
		},
	}

	var gitRev string

	siteCmd := &cobra.Command{
		Use:   "site",
		Short: "Generate Markdown documentation for settings and modules",
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Println("generating settings documentation")

			generatedSettingsPath := filepath.Join("doc", "src", "generated-settings.md")
			if err := generateSettingsDocMarkdown(generatedSettingsPath); err != nil {
				return err
			}

			fmt.Println("generating module documentation")

			generatedModulePath := filepath.Join("doc", "src", "generated-module.md")
			if err := generateModuleDoc(generatedModulePath, gitRev); err != nil {
				return err
			}

			fmt.Println("generated settings and modules for mdbook site")

			return nil
		},
	}
	siteCmd.Flags().StringVarP(&gitRev, "revision", "r", "main", "Git rev to use when generating module doc links")

	var outputManDir string

	manCmd := &cobra.Command{
		Use:   "man",
		Short: "Generate man pages using scdoc",
		RunE: func(cmd *cobra.Command, args []string) error {
			return generateManPages(filepath.Join("doc", "man"), outputManDir)
		},
	}
	manCmd.Flags().StringVarP(&outputManDir, "output", "o", "man", "Where to place generated man pages")

	rootCmd.AddCommand(siteCmd, manCmd)

	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func generateSettingsDocMarkdown(filename string) error {
	var sb strings.Builder

	defaults := *settings.NewSettings()

	writeSettingsDoc(reflect.TypeOf(defaults), reflect.ValueOf(defaults), "", &sb, 2, MarkdownSettingsFormatter{})

	return os.WriteFile(filename, []byte(sb.String()), 0o644)
}

//go:embed man/nixos-cli-settings.5.scd.template
var settingsTemplate string

func generateSettingsDocManpage(filename string) error {
	var sb strings.Builder

	defaults := *settings.NewSettings()

	writeSettingsDoc(reflect.TypeOf(defaults), reflect.ValueOf(defaults), "", &sb, 2, ManpageSettingsFormatter{})

	contents := fmt.Sprintf(settingsTemplate, sb.String())

	return os.WriteFile(filename, []byte(contents), 0o644)
}

func generateModuleDoc(filename string, rev string) error {
	var sb strings.Builder

	cmd := exec.Command("nix-options-doc", "--strip-prefix")
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

	repoBaseURL := fmt.Sprintf("https://github.com/nix-community/nixos-cli/blob/%s", rev)

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

type SettingsFormatter interface {
	WriteHeader(sb *strings.Builder, title string, level int)
	WriteSectionDescription(sb *strings.Builder, desc string)
	WriteItem(sb *strings.Builder, key string, desc string, defaultValue string)
}

type MarkdownSettingsFormatter struct{}

func (f MarkdownSettingsFormatter) WriteHeader(sb *strings.Builder, title string, level int) {
	fmt.Fprintf(sb, "%s %s\n\n", strings.Repeat("#", level), title)
}

func (MarkdownSettingsFormatter) WriteSectionDescription(sb *strings.Builder, desc string) {
	sb.WriteString(desc + "\n\n")
}

func (f MarkdownSettingsFormatter) WriteItem(sb *strings.Builder, key, desc, defaultValue string) {
	fmt.Fprintf(sb, "- **%s**\n\n  %s\n\n  **Default**: `%s`\n\n", key, desc, defaultValue)
}

type ManpageSettingsFormatter struct{}

func (f ManpageSettingsFormatter) WriteHeader(sb *strings.Builder, title string, level int) {
	fmt.Fprintf(sb, "\n%s %s\n", strings.Repeat("#", level), strings.ToUpper(title))
}

func (ManpageSettingsFormatter) WriteSectionDescription(sb *strings.Builder, desc string) {
	sb.WriteString(desc + "\n\n")
}

func (f ManpageSettingsFormatter) WriteItem(sb *strings.Builder, key, desc, defaultValue string) {
	fmt.Fprintf(sb, "\n*%s*\n\n%s\n\nDefault: _%s_\n", key, desc, defaultValue)
}

func writeSettingsDoc(
	t reflect.Type,
	v reflect.Value,
	path string,
	sb *strings.Builder,
	depth int,
	formatter SettingsFormatter,
) {
	type nestedField struct {
		field    reflect.StructField
		fieldVal reflect.Value
		fullKey  string
	}

	type configKey struct {
		key          string
		desc         string
		defaultValue string
	}

	var generalItems []configKey
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
			generalItems = append(generalItems, configKey{fullKey, desc, defaultVal})
		}
	}

	if len(generalItems) > 0 {
		if path == "" {
			formatter.WriteHeader(sb, "General", 2)
		}

		sort.Slice(generalItems, func(i, j int) bool {
			return generalItems[i].key < generalItems[j].key
		})

		for _, item := range generalItems {
			formatter.WriteItem(sb, item.key, item.desc, item.defaultValue)
		}
	}

	for _, entry := range nestedFields {
		descriptions := settings.SettingsDocs[entry.fullKey]
		desc := descriptions.Long
		if desc == "" {
			desc = descriptions.Short
		}

		formatter.WriteHeader(sb, entry.fullKey, depth)
		formatter.WriteSectionDescription(sb, desc)
		writeSettingsDoc(entry.field.Type, entry.fieldVal, entry.fullKey+".", sb, depth+1, formatter)
	}
}

func formatValue(v reflect.Value) string {
	if !v.IsValid() {
		return "n/a"
	}
	switch v.Kind() {
	case reflect.String:
		if v.String() == "" {
			return `""`
		}
		return fmt.Sprintf(`"%s"`, v.String())
	case reflect.Bool:
		return fmt.Sprintf("%t", v.Bool())
	case reflect.Int, reflect.Int64:
		return fmt.Sprintf("%d", v.Int())
	case reflect.Map, reflect.Slice:
		if v.Len() == 0 {
			return "[]"
		}
		return "(multiple entries)"
	default:
		return fmt.Sprintf("%v", v.Interface())
	}
}

func generateManPages(inputDir string, outputDir string) error {
	generatedSettingsManPagePath := filepath.Join("doc", "man", "nixos-cli-settings.5.scd")

	if err := generateSettingsDocManpage(generatedSettingsManPagePath); err != nil {
		return err
	}

	return filepath.WalkDir(inputDir, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}

		if filepath.Ext(path) != ".scd" {
			return nil
		}

		content, readErr := os.ReadFile(path)
		if readErr != nil {
			return fmt.Errorf("failed to read %s: %w", path, readErr)
		}

		cmd := exec.Command("scdoc")
		cmd.Stdin = bytes.NewReader(content)

		var outBuf bytes.Buffer
		cmd.Stdout = &outBuf
		cmd.Stderr = os.Stderr

		if err := cmd.Run(); err != nil {
			return fmt.Errorf("scdoc failed for %s: %w", path, err)
		}

		base := filepath.Base(path)
		manFile := base[:len(base)-len(".scd")]
		outPath := filepath.Join(outputDir, manFile)

		if err := os.MkdirAll(outputDir, 0o755); err != nil {
			return err
		}

		if writeErr := os.WriteFile(outPath, outBuf.Bytes(), 0o644); writeErr != nil {
			return fmt.Errorf("failed to write %s: %w", outPath, writeErr)
		}

		fmt.Printf("generated %s\n", outPath)
		return nil
	})
}
