package option

import (
	"slices"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/termenv"

	"github.com/sahilm/fuzzy"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
	"github.com/water-sucks/nixos/internal/option"
	"github.com/water-sucks/nixos/internal/settings"
)

var (
	titleStyle = lipgloss.NewStyle().Bold(true).Align(lipgloss.Center)

	inactiveBorderStyle = lipgloss.NewStyle().Border(lipgloss.NormalBorder())
	focusedBorderStyle  = lipgloss.NewStyle().
				Border(lipgloss.NormalBorder()).
				BorderForeground(lipgloss.ANSIColor(termenv.ANSIMagenta))

	marginStyle = lipgloss.NewStyle().Margin(2, 2)
)

type Model struct {
	focus FocusArea

	options    option.NixosOptionSource
	filtered   []fuzzy.Match
	minScore   int64
	debounce   int64
	debounceID int

	search  SearchBarModel
	results ResultListModel
	preview PreviewModel
}

type FocusArea int

const (
	FocusAreaResults FocusArea = iota
	FocusAreaPreview
)

func NewModel(options option.NixosOptionSource, cfg *settings.OptionSettings) Model {
	preview := NewPreviewModel(cfg.Prettify)
	search := NewSearchBarModel(len(options)).
		SetFocused(true)
	results := NewResultListModel(options)

	return Model{
		options:  options,
		minScore: cfg.MinScore,

		focus:    FocusAreaResults,
		debounce: cfg.DebounceTime,

		results: results,
		preview: preview,
		search:  search,
	}
}

func (m Model) Init() tea.Cmd {
	return nil
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c":
			return m, tea.Quit

		case "tab":
			m = m.toggleFocus()
		}

	case tea.WindowSizeMsg:
		m = m.updateWindowSize(msg.Width, msg.Height)
		// Force a re-render. The option string is cached otherwise,
		// and this can screw with the centered portion.
		m.preview = m.preview.ForceContentUpdate()

	case searchMsg:
		if msg.id != m.debounceID {
			// Explicitly return the model early here, since this
			// is a stale debounce command; there's no need to rebuild
			// the UI off this message.
			return m, nil
		}
		m = m.runSearch(msg.query)
	}

	var cmds []tea.Cmd

	newSearch, tiCmd := m.search.Update(msg)
	cmds = append(cmds, tiCmd)

	oldQuery := m.search.Value()
	m.search = newSearch
	query := m.search.Value()

	// Re-run the fuzzy search query only when it changes.
	// This may need a debounce later.
	if query != oldQuery {
		m.debounceID++
		cmds = append(cmds, searchCmd(m, query))
	}

	var resultsCmd tea.Cmd
	m.results, resultsCmd = m.results.Update(msg)
	cmds = append(cmds, resultsCmd)

	m.search = m.search.SetResultCount(len(m.filtered))

	selectedOption := m.results.GetSelectedOption()
	m.preview = m.preview.SetOption(selectedOption)

	var previewCmd tea.Cmd
	m.preview, previewCmd = m.preview.Update(msg)
	cmds = append(cmds, previewCmd)

	return m, tea.Batch(cmds...)
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

type searchMsg struct {
	id    int
	query string
}

func searchCmd(m Model, query string) tea.Cmd {
	delay := time.Duration(m.debounce) * time.Millisecond
	return tea.Tick(delay, func(t time.Time) tea.Msg {
		return searchMsg{
			id:    m.debounceID,
			query: query,
		}
	})
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
	marginX := 2
	marginY := 2
	borderPadding := 2

	usableWidth := width - marginX
	usableHeight := height - marginY

	leftWidth := (usableWidth + 1) / 2
	rightWidth := usableWidth - leftWidth

	searchHeight := 3

	m.results = m.results.
		SetWidth(leftWidth - borderPadding).
		SetHeight(usableHeight - searchHeight - borderPadding)

	m.search = m.search.
		SetWidth(leftWidth - borderPadding).
		SetHeight(searchHeight)

	m.preview = m.preview.ScrollDown().
		SetWidth(rightWidth - borderPadding).
		SetHeight(usableHeight - borderPadding)

	return m
}

func (m Model) View() string {
	results := m.results.View()
	search := m.search.View()
	preview := m.preview.View()

	left := lipgloss.JoinVertical(lipgloss.Top, results, search)

	main := lipgloss.JoinHorizontal(lipgloss.Top, left, preview)

	return marginStyle.Render(main)
}

func optionTUI(options option.NixosOptionSource, cfg *settings.OptionSettings) error {
	closeLogFile, _ := cmdUtils.ConfigureBubbleTeaLogger("option-tui")
	defer closeLogFile()

	p := tea.NewProgram(NewModel(options, cfg), tea.WithAltScreen())

	if _, err := p.Run(); err != nil {
		return err
	}

	return nil
}
