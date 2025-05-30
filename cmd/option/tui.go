package option

import (
	"os/exec"
	"slices"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/termenv"

	"github.com/nix-community/nixos-cli/internal/cmd/utils"
	"github.com/nix-community/nixos-cli/internal/configuration"
	"github.com/nix-community/nixos-cli/internal/settings"
	"github.com/sahilm/fuzzy"
	"github.com/water-sucks/optnix/option"
)

var (
	titleStyle = lipgloss.NewStyle().Bold(true).Align(lipgloss.Center)

	inactiveBorderStyle = lipgloss.NewStyle().Border(lipgloss.NormalBorder())
	focusedBorderStyle  = lipgloss.NewStyle().
				Border(lipgloss.NormalBorder()).
				BorderForeground(lipgloss.ANSIColor(termenv.ANSIMagenta))
	titleRuleStyle = lipgloss.NewStyle().
			Border(lipgloss.NormalBorder()).
			BorderForeground(lipgloss.ANSIColor(termenv.ANSIWhite)).
			BorderTop(true).
			BorderRight(false).
			BorderBottom(false).
			BorderLeft(false)

	marginStyle = lipgloss.NewStyle().Margin(2, 2, 0, 2)
	hintStyle   = lipgloss.NewStyle().
			Foreground(lipgloss.ANSIColor(termenv.ANSIYellow)) // Soft gray

)

type Model struct {
	focus FocusArea
	mode  ViewMode

	options option.NixosOptionSource
	cfg     configuration.Configuration

	filtered []fuzzy.Match
	minScore int64

	width  int
	height int

	search  SearchBarModel
	results ResultListModel
	preview PreviewModel
	eval    EvalValueModel
}

type ViewMode int

const (
	ViewModeSearch = iota
	ViewModeEvalValue
)

type ChangeViewModeMsg ViewMode

type FocusArea int

const (
	FocusAreaResults FocusArea = iota
	FocusAreaPreview
)

func NewModel(options option.NixosOptionSource, nixosConfig configuration.Configuration, cfg *settings.OptionSettings, initialInput string) Model {
	preview := NewPreviewModel(cfg.Prettify)
	search := NewSearchBarModel(len(options)).
		SetFocused(true).
		SetValue(initialInput)
	results := NewResultListModel(options).
		SetFocused(true)
	eval := NewEvalValueModel(nixosConfig)

	return Model{
		mode:  ViewModeSearch,
		focus: FocusAreaResults,

		options: options,
		cfg:     nixosConfig,

		minScore: cfg.MinScore,

		results: results,
		preview: preview,
		search:  search,
		eval:    eval,
	}
}

func (m Model) Init() tea.Cmd {
	if m.search.Value() != "" {
		return func() tea.Msg {
			return RunSearchMsg{Query: m.search.Value()}
		}
	}

	return nil
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c":
			return m, tea.Quit
		}
	case tea.WindowSizeMsg:
		m = m.updateWindowSize(msg.Width, msg.Height)

		// Always forward resize events to components that need them.
		m.eval, _ = m.eval.Update(msg)

		return m, nil

	case ChangeViewModeMsg:
		m.mode = ViewMode(msg)

	case EvalValueStartMsg:
		m.mode = ViewMode(ViewModeEvalValue)
	}

	switch m.mode {
	case ViewModeSearch:
		return m.updateSearch(msg)
	case ViewModeEvalValue:
		var evalCmd tea.Cmd
		m.eval, evalCmd = m.eval.Update(msg)
		return m, evalCmd
	}

	return m, nil
}

func (m Model) updateSearch(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "tab":
			m = m.toggleFocus()

		case "ctrl+g":
			return m, m.openHelpManPage()
		}
	case RunSearchMsg:
		m = m.runSearch(msg.Query)
		m.search = m.search.SetResultCount(len(m.filtered))
	}

	var cmds []tea.Cmd

	var searchCmd tea.Cmd
	m.search, searchCmd = m.search.Update(msg)
	cmds = append(cmds, searchCmd)

	var resultsCmd tea.Cmd
	m.results, resultsCmd = m.results.Update(msg)
	cmds = append(cmds, resultsCmd)

	selectedOption := m.results.GetSelectedOption()
	m.preview = m.preview.SetOption(selectedOption)

	var previewCmd tea.Cmd
	m.preview, previewCmd = m.preview.Update(msg)
	cmds = append(cmds, previewCmd)

	return m, tea.Batch(cmds...)
}

type ManFinishedMsg struct{}

func (m Model) openHelpManPage() tea.Cmd {
	cmd := exec.Command("man", "nixos-cli-option-tui")
	return tea.ExecProcess(cmd, func(err error) tea.Msg {
		return ManFinishedMsg{}
	})
}

func (m Model) runSearch(query string) Model {
	allMatches := fuzzy.FindFrom(query, m.options)
	m.filtered = filterMinimumScoreMatches(allMatches, int(m.minScore))

	slices.Reverse(m.filtered)

	m.results = m.results.
		SetResultList(m.filtered).
		SetSelectedIndex(len(m.filtered) - 1)

	return m
}

type RunSearchMsg struct {
	Query string
}

func (m Model) toggleFocus() Model {
	switch m.focus {
	case FocusAreaResults:
		m.focus = FocusAreaPreview

		m.results = m.results.SetFocused(false)
		m.search = m.search.SetFocused(false)
		m.preview = m.preview.SetFocused(true)
	case FocusAreaPreview:
		m.focus = FocusAreaResults

		m.results = m.results.SetFocused(true)
		m.search = m.search.SetFocused(true)
		m.preview = m.preview.SetFocused(false)
	}

	return m
}

func (m Model) updateWindowSize(width, height int) Model {
	m.width = width
	m.height = height

	usableWidth := width - 4   // 2 left + 2 right margins
	usableHeight := height - 2 // 2 top margin

	searchHeight := 3

	halfWidth := usableWidth / 2

	m.results = m.results.
		SetWidth(halfWidth - 2). // 1 border each side
		SetHeight(usableHeight - searchHeight - 2)

	m.search = m.search.
		SetWidth(halfWidth - 2).
		SetHeight(searchHeight)

	m.preview = m.preview.
		SetWidth(halfWidth - 2).
		SetHeight(usableHeight - 2)

	return m
}

func (m Model) View() string {
	switch m.mode {
	case ViewModeEvalValue:
		return marginStyle.Render(m.eval.View())
	}

	results := m.results.View()
	search := m.search.View()
	preview := m.preview.View()

	left := lipgloss.JoinVertical(lipgloss.Top, results, search)
	main := lipgloss.JoinHorizontal(lipgloss.Top, left, preview)

	hint := lipgloss.PlaceHorizontal(m.width, lipgloss.Center, hintStyle.Render("For basic help, press Ctrl-G."))

	return lipgloss.JoinVertical(
		lipgloss.Top,
		marginStyle.Render(main),
		hint,
	)
}

func optionTUI(options option.NixosOptionSource, nixosConfig configuration.Configuration, settings *settings.OptionSettings, initialInput string) error {
	closeLogFile, _ := cmdUtils.ConfigureBubbleTeaLogger("option-tui")
	defer closeLogFile()

	p := tea.NewProgram(NewModel(options, nixosConfig, settings, initialInput), tea.WithAltScreen())

	if _, err := p.Run(); err != nil {
		return err
	}

	return nil
}
