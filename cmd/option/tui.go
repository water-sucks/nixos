package option

import (
	"fmt"
	"os"
	"slices"
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/termenv"

	"github.com/sahilm/fuzzy"
	"github.com/water-sucks/nixos/internal/option"
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

	focus focusArea

	candidates  option.NixosOptionSource
	textinput   textinput.Model
	filtered    []fuzzy.Match
	selectedIdx int
	startRow    int

	resultsWidth  int
	resultsHeight int
	searchWidth   int
	searchHeight  int

	preview viewport.Model
}

type focusArea int

const (
	focusResults focusArea = iota
	focusPreview
)

func newModel(options option.NixosOptionSource, minScore int64) model {
	ti := textinput.New()
	ti.Placeholder = "Search for options..."
	ti.Prompt = "> "
	ti.Focus()

	preview := viewport.New(0, 0)

	return model{
		candidates: options,
		textinput:  ti,
		minScore:   minScore,
		preview:    preview,
	}
}

func (m *model) resultCountStr() string {
	if query := m.textinput.Value(); query != "" {
		return fmt.Sprintf("%d/%d", len(m.filtered), len(m.candidates))
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
			if m.focus == focusResults {
				m.focus = focusPreview
				m.textinput.Blur()
			} else {
				m.focus = focusResults
				m.textinput.Focus()
			}

		case "up":
			if m.focus == focusResults {
				if m.selectedIdx > 0 {
					m.selectedIdx--
					if m.selectedIdx < m.startRow {
						m.startRow--
					}
				}
			} else {
				m.preview.LineUp(1)
			}

		case "down":
			if m.focus == focusResults {
				if m.selectedIdx < len(m.filtered)-1 {
					m.selectedIdx++

					if m.selectedIdx >= m.startRow+m.visibleResultRows() {
						m.startRow++
					}
				}
			} else {
				m.preview.LineDown(1)
			}
		}

	case tea.WindowSizeMsg:
		marginX := 2 // 2 on left + 2 on right
		marginY := 2 // 2 on top + 2 on bottom
		borderPadding := 2

		usableWidth := msg.Width - marginX
		usableHeight := msg.Height - marginY

		leftWidth := (usableWidth + 1) / 2
		rightWidth := usableWidth - leftWidth

		m.searchWidth = leftWidth - borderPadding
		m.searchHeight = 3

		m.resultsWidth = leftWidth - borderPadding
		m.resultsHeight = usableHeight - m.searchHeight - borderPadding

		m.preview.Width = rightWidth - borderPadding
		m.preview.Height = usableHeight - borderPadding

	}

	newTextInput, tiCmd := m.textinput.Update(msg)

	query := newTextInput.Value()
	oldQuery := m.textinput.Value()

	// Re-run the fuzzy search query only when it changes.
	// This may need a debounce later.
	if query != oldQuery {
		allMatches := fuzzy.FindFrom(query, m.candidates)
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

	newPreview, resultViewCmd := m.preview.Update(msg)
	m.preview = newPreview

	m.textinput = newTextInput
	return m, tea.Batch(tiCmd, resultViewCmd)
}

func (m model) View() string {
	results := m.renderResultsView()
	search := m.renderSearchBar()
	preview := m.renderOptionPreview()

	leftPane := lipgloss.JoinVertical(lipgloss.Top, results, search)
	main := lipgloss.JoinHorizontal(lipgloss.Top, leftPane, preview)

	return marginStyle.Render(main)
}

func (m model) renderResultsView() string {
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
		candidate := m.candidates[m.filtered[i].Index]

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

func (m model) renderOptionPreview() string {
	var opt *option.NixosOption
	if len(m.filtered) > 0 && m.selectedIdx >= 0 {
		opt = &m.candidates[m.filtered[m.selectedIdx].Index]
	}

	title := lipgloss.PlaceHorizontal(m.preview.Width, lipgloss.Center, titleStyle.Render("Option Preview"))
	content := title + "\n\nSelected: "
	if opt != nil {
		content += opt.Name
	} else {
		content += "None"
	}

	m.preview.Style = m.getBorderStyle(focusPreview)

	m.preview.SetContent(content)

	return m.preview.View()
}

func optionTUI(options option.NixosOptionSource, minScore int64) {
	logFile, err := tea.LogToFile("debug.log", "debug")
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to create log file: %v\n", err)
		return
	}
	defer func() { _ = logFile.Close() }()

	p := tea.NewProgram(newModel(options, minScore), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Println("Error:", err)
		os.Exit(1)
	}
}
