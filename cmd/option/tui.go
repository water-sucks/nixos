package option

import (
	"fmt"
	"os"
	"slices"
	"strings"

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
	minScore int64

	focus FocusArea

	options     option.NixosOptionSource
	filtered    []fuzzy.Match
	selectedIdx int
	startRow    int

	resultsWidth  int
	resultsHeight int

	search  SearchBarModel
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

	return Model{
		options:  options,
		minScore: minScore,

		focus:   FocusAreaResults,
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
		allMatches := fuzzy.FindFrom(query, m.options)
		m.filtered = filterMinimumScoreMatches(allMatches, int(m.minScore))

		slices.Reverse(m.filtered)

		m.selectedIdx = len(m.filtered) - 1
		visible := min(m.visibleResultRows(), len(m.filtered))
		m.startRow = max(m.selectedIdx-(visible-1), 0)
	}

	m.search = m.search.SetResultCount(len(m.filtered))

	// Make sure that resizes don't result in the start row ending
	// up past an impossible index (i.e. there will be empty space
	// on the bottom of the screen).
	maxStart := max(len(m.filtered)-m.visibleResultRows(), 0)
	if m.startRow > maxStart {
		m.startRow = maxStart
	}

	var selectedOption *option.NixosOption
	if m.selectedIdx >= 0 && len(m.filtered) > 0 {
		optionIdx := m.filtered[m.selectedIdx].Index
		selectedOption = &m.options[optionIdx]
	}

	m.preview = m.preview.SetOption(selectedOption)

	var previewCmd tea.Cmd
	m.preview, previewCmd = m.preview.Update(msg)
	cmds = append(cmds, previewCmd)

	return m, tea.Batch(cmds...)
}

func (m Model) visibleResultRows() int {
	return m.resultsHeight - 3 // one for title, two for borders
}

func (m Model) updateFocus() Model {
	if m.focus == FocusAreaResults {
		m.focus = FocusAreaPreview
		m.search = m.search.SetFocused(false)
		m.preview = m.preview.SetFocused(true)
	} else {
		m.focus = FocusAreaResults
		m.search = m.search.SetFocused(true)
		m.preview = m.preview.SetFocused(false)
	}

	return m
}

func (m Model) updateScrollUp() Model {
	if m.focus == FocusAreaResults {
		// Scrolling up in the results list means accessing less
		// relevant results.
		if m.selectedIdx > 0 {
			m.selectedIdx--

			if m.selectedIdx < m.startRow {
				m.startRow--
			}
		}
	} else {
		m.preview = m.preview.ScrollUp()
	}

	return m
}

func (m Model) updateScrollDown() Model {
	if m.focus == FocusAreaResults {
		// Scrolling down in the results list means accessing more
		// relevant results.
		if m.selectedIdx < len(m.filtered)-1 {
			m.selectedIdx++

			if m.selectedIdx >= m.startRow+m.visibleResultRows() {
				m.startRow++
			}
		}
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

	m.resultsWidth = leftWidth - borderPadding
	m.resultsHeight = usableHeight - searchHeight - borderPadding

	m.search = m.search.
		SetWidth(leftWidth - borderPadding).
		SetHeight(searchHeight)

	m.preview = m.preview.ScrollDown().
		SetWidth(rightWidth - borderPadding).
		SetHeight(usableHeight - borderPadding)

	return m
}

func (m Model) View() string {
	results := m.renderResultsView()
	search := m.search.View()
	preview := m.preview.View()

	left := lipgloss.JoinVertical(lipgloss.Top, results, search)

	main := lipgloss.JoinHorizontal(lipgloss.Top, left, preview)

	return marginStyle.Render(main)
}

func (m Model) renderResultsView() string {
	title := lipgloss.PlaceHorizontal(m.resultsWidth, lipgloss.Center, titleStyle.Render("Results"))

	height := m.visibleResultRows()

	start := m.startRow
	end := min(start+height, len(m.filtered))

	lines := []string{}

	// Add padding, if necessary.
	linesOfPadding := height - len(m.filtered)
	for range linesOfPadding {
		lines = append(lines, "")
	}

	for i := start; i < end; i++ {
		candidate := m.options[m.filtered[i].Index]

		line := lipgloss.NewStyle().
			Width(m.resultsWidth).
			Render(candidate.Name)

		style := resultItemStyle
		if i == m.selectedIdx {
			style = selectedResultStyle
		}
		lines = append(lines, style.Width(m.resultsWidth).Render(line))

	}

	body := strings.Join(lines, "\n")

	style := m.getBorderStyle(FocusAreaResults)

	return style.Width(m.resultsWidth).Render(title + "\n" + body)
}

func (m Model) getBorderStyle(area FocusArea) lipgloss.Style {
	if area == m.focus {
		return focusedBorderStyle
	}
	return inactiveBorderStyle
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
