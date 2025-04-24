package option

import (
	"fmt"
	"os"
	"slices"
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/termenv"

	"github.com/sahilm/fuzzy"
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

type model struct {
	minScore int64
	prettify bool

	focus focusArea

	options     option.NixosOptionSource
	textinput   textinput.Model
	filtered    []fuzzy.Match
	selectedIdx int
	startRow    int

	resultsWidth  int
	resultsHeight int
	searchWidth   int
	searchHeight  int

	preview PreviewModel
}

type focusArea int

const (
	focusResults focusArea = iota
	focusPreview
)

func newModel(options option.NixosOptionSource, minScore int64, prettify bool) model {
	ti := textinput.New()
	ti.Placeholder = "Search for options..."
	ti.Prompt = "> "
	ti.Focus()

	preview := NewPreviewModel(prettify)

	return model{
		options:   options,
		minScore:  minScore,
		prettify:  prettify,
		preview:   preview,
		textinput: ti,
		focus:     focusResults,
	}
}

func (m *model) resultCountStr() string {
	if query := m.textinput.Value(); query != "" {
		return fmt.Sprintf("%d/%d", len(m.filtered), len(m.options))
	}
	return ""
}

func (m model) visibleResultRows() int {
	return m.resultsHeight - 3 // one for title, two for borders
}

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
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

			// TODO: implement left/right scrolling for the preview viewport
			// This is already in a `bubbles` release, just needs to be updated.
		}

	case tea.WindowSizeMsg:
		m = m.updateWindowSize(msg.Width, msg.Height)
		// Force a re-render. The option string is cached.
		m.preview = m.preview.ForceContentUpdate()
	}

	var cmds []tea.Cmd

	newTextInput, tiCmd := m.textinput.Update(msg)
	cmds = append(cmds, tiCmd)

	query := newTextInput.Value()
	oldQuery := m.textinput.Value()

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

	m.textinput = newTextInput

	return m, tea.Batch(cmds...)
}

func (m model) updateFocus() model {
	if m.focus == focusResults {
		m.focus = focusPreview
		m.textinput.Blur()
		m.preview = m.preview.SetFocused(true)
	} else {
		m.focus = focusResults
		m.textinput.Focus()
		m.preview = m.preview.SetFocused(false)
	}

	return m
}

func (m model) updateScrollUp() model {
	if m.focus == focusResults {
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

func (m model) updateScrollDown() model {
	if m.focus == focusResults {
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

func (m model) updateWindowSize(width, height int) model {
	marginX := 2
	marginY := 2
	borderPadding := 2

	usableWidth := width - marginX
	usableHeight := height - marginY

	leftWidth := (usableWidth + 1) / 2
	rightWidth := usableWidth - leftWidth

	m.searchWidth = leftWidth - borderPadding
	m.searchHeight = 3

	m.resultsWidth = leftWidth - borderPadding
	m.resultsHeight = usableHeight - m.searchHeight - borderPadding

	m.preview = m.preview.ScrollDown().
		SetWidth(rightWidth - borderPadding).
		SetHeight(usableHeight - borderPadding)

	return m
}

func (m model) View() string {
	results := m.renderResultsView()
	search := m.renderSearchBar()
	preview := m.preview.View()

	left := lipgloss.JoinVertical(lipgloss.Top, results, search)

	main := lipgloss.JoinHorizontal(lipgloss.Top, left, preview)

	return marginStyle.Render(main)
}

func (m *model) renderResultsView() string {
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

	style := m.getBorderStyle(focusResults)

	return style.Width(m.resultsWidth).Render(title + "\n" + body)
}

func (m model) renderSearchBar() string {
	left := m.textinput.View()
	right := m.resultCountStr()

	rightWidth := lipgloss.Width(right)
	spaceBetween := 1

	maxLeftWidth := max(m.searchWidth-rightWidth-spaceBetween, 0)
	leftWidth := lipgloss.Width(left)
	if leftWidth > maxLeftWidth {
		left = truncateString(left, maxLeftWidth)
	}

	padding := m.searchWidth - lipgloss.Width(left) - rightWidth
	style := m.getBorderStyle(focusResults)

	return style.Width(m.searchWidth).Render(left + strings.Repeat(" ", padding) + right)
}

func truncateString(s string, width int) string {
	runes := []rune(s)
	if len(runes) <= width {
		return s
	}
	return string(runes[:width])
}

func (m model) getBorderStyle(area focusArea) lipgloss.Style {
	if area == m.focus {
		return focusedBorderStyle
	}
	return inactiveBorderStyle
}

func optionTUI(options option.NixosOptionSource, cfg *settings.OptionSettings) {
	p := tea.NewProgram(newModel(options, cfg.MinScore, cfg.Prettify), tea.WithAltScreen())

	if _, err := p.Run(); err != nil {
		fmt.Println("Error:", err)
		os.Exit(1)
	}
}
