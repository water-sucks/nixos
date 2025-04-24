package option

import (
	"fmt"
	"os"
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

	selectedResultStyle = lipgloss.NewStyle().
				Background(lipgloss.ANSIColor(termenv.ANSIBlue)).
				Foreground(lipgloss.ANSIColor(termenv.ANSIBrightWhite)).
				Padding(0, 2)
	resultItemStyle = lipgloss.NewStyle().Padding(0, 2)

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

func NewModel(options option.NixosOptionSource, minScore int64, prettify bool) Model {
	preview := NewPreviewModel(prettify)
	search := NewSearchBarModel(len(options)).
		SetFocused(true)
	results := NewResultListModel(options)

	return Model{
		options:  options,
		minScore: minScore,
		debounce: 25,

		focus: FocusAreaResults,

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
			m = m.updateFocus()

		case "up":
			m = m.updateScrollUp()

		case "down":
			m = m.updateScrollDown()

		case "left":
			m = m.updateScrollLeft()

		case "right":
			m = m.updateScrollRight()
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

func (m Model) updateFocus() Model {
	if m.focus == FocusAreaResults {
		m.focus = FocusAreaPreview

		m.results = m.results.SetFocused(false)
		m.search = m.search.SetFocused(false)
		m.preview = m.preview.SetFocused(true)
	} else {
		m.focus = FocusAreaResults

		m.results = m.results.SetFocused(true)
		m.search = m.search.SetFocused(true)
		m.preview = m.preview.SetFocused(false)
	}

	return m
}

func (m Model) updateScrollUp() Model {
	if m.focus == FocusAreaResults {
		m.results = m.results.ScrollUp()
	} else {
		m.preview = m.preview.ScrollUp()
	}

	return m
}

func (m Model) updateScrollDown() Model {
	if m.focus == FocusAreaResults {
		m.results = m.results.ScrollDown()
	} else {
		m.preview = m.preview.ScrollDown()
	}
	return m
}

func (m Model) updateScrollLeft() Model {
	if m.focus != FocusAreaResults {
		return m
	}

	m.preview.ScrollLeft()
	return m
}

func (m Model) updateScrollRight() Model {
	if m.focus != FocusAreaResults {
		return m
	}

	m.preview.ScrollRight()
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

func optionTUI(options option.NixosOptionSource, cfg *settings.OptionSettings) {
	closeLogFile, _ := cmdUtils.ConfigureBubbleTeaLogger("option-tui")
	defer closeLogFile()

	p := tea.NewProgram(NewModel(options, cfg.MinScore, cfg.Prettify), tea.WithAltScreen())

	if _, err := p.Run(); err != nil {
		fmt.Println("Error:", err)
		os.Exit(1)
	}
}
