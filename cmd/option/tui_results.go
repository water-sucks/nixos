package option

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/termenv"
	"github.com/sahilm/fuzzy"
	"github.com/water-sucks/optnix/option"
)

var (
	selectedResultStyle = lipgloss.NewStyle().
				Background(lipgloss.ANSIColor(termenv.ANSIBlue)).
				Foreground(lipgloss.ANSIColor(termenv.ANSIBrightWhite)).
				Padding(0, 2)
	resultItemStyle  = lipgloss.NewStyle().Padding(0, 2)
	matchedCharStyle = lipgloss.NewStyle().
				Foreground(lipgloss.ANSIColor(termenv.ANSIGreen)).
				Bold(true)
	unmatchedCharStyle = lipgloss.NewStyle().
				Foreground(lipgloss.ANSIColor(termenv.ANSIBrightWhite))
)

type ResultListModel struct {
	options  option.NixosOptionSource
	filtered []fuzzy.Match

	focused bool

	selected int
	start    int

	width  int
	height int
}

func NewResultListModel(options option.NixosOptionSource) ResultListModel {
	return ResultListModel{
		options: options,
	}
}

func (m ResultListModel) SetResultList(matches []fuzzy.Match) ResultListModel {
	m.filtered = matches
	return m
}

func (m ResultListModel) SetSelectedIndex(index int) ResultListModel {
	m.selected = index

	// Also set the starting index for the window. This is needed
	// for smooth scrolling.
	visible := min(m.visibleResultRows(), len(m.filtered))
	m.start = max(m.selected-(visible-1), 0)

	return m
}

func (m ResultListModel) SetFocused(focus bool) ResultListModel {
	m.focused = focus
	return m
}

func (m ResultListModel) SetWidth(width int) ResultListModel {
	m.width = width
	return m
}

func (m ResultListModel) SetHeight(height int) ResultListModel {
	m.height = height
	return m
}

// Scroll up one entry in the result list window. Note that
// scrolling up in the results list means less relevant results.
func (m ResultListModel) ScrollUp() ResultListModel {
	if !m.focused {
		return m
	}

	if m.selected > 0 {
		m.selected--

		if m.selected < m.start && m.start > 0 {
			m.start--
		}
	}

	return m
}

func (m ResultListModel) ScrollDown() ResultListModel {
	if !m.focused {
		return m
	}

	if m.selected < len(m.filtered)-1 {
		m.selected++

		if m.selected >= m.start+m.visibleResultRows() {
			m.start++
		}
	}

	return m
}

func (m ResultListModel) GetSelectedOption() *option.NixosOption {
	if m.selected >= 0 && len(m.filtered) > 0 {
		optionIdx := m.filtered[m.selected].Index
		return &m.options[optionIdx]
	}

	return nil
}

func (m ResultListModel) Update(msg tea.Msg) (ResultListModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "up":
			m = m.ScrollUp()

		case "down":
			m = m.ScrollDown()

		case "enter":
			if len(m.filtered) < 1 {
				return m, nil
			}

			changeModeCmd := func() tea.Msg {
				o := m.options[m.filtered[m.selected].Index]
				return EvalValueStartMsg{Option: o.Name}
			}

			return m, changeModeCmd
		}
	}

	// Make sure that resizes don't result in the start row ending
	// up past an impossible index (i.e. there will be empty space
	// on the bottom of the screen).
	maxStart := max(len(m.filtered)-m.visibleResultRows(), 0)
	if m.start > maxStart {
		m.start = maxStart
	}

	return m, nil
}

func (m ResultListModel) View() string {
	title := lipgloss.PlaceHorizontal(m.width, lipgloss.Center, titleStyle.Render("Results"))

	height := m.visibleResultRows()

	end := min(m.start+height, len(m.filtered))

	lines := []string{}

	// Add padding, if necessary.
	linesOfPadding := height - len(m.filtered)
	for range linesOfPadding {
		lines = append(lines, "")
	}

	for i := m.start; i < end; i++ {
		match := m.filtered[i]
		o := m.options[match.Index]

		name := o.Name
		matched := map[int]struct{}{}
		for _, idx := range match.MatchedIndexes {
			matched[idx] = struct{}{}
		}

		style := resultItemStyle
		if i == m.selected {
			style = selectedResultStyle
		}

		var b strings.Builder
		for j, r := range name {
			s := unmatchedCharStyle
			if _, ok := matched[j]; ok {
				s = matchedCharStyle
			}

			b.WriteString(s.Inherit(style).Render(string(r)))
		}

		line := style.Width(m.width).MaxHeight(1).Render(b.String())
		lines = append(lines, line)

	}

	body := strings.Join(lines, "\n")

	style := inactiveBorderStyle
	if m.focused {
		style = focusedBorderStyle
	}

	return style.Width(m.width).Render(title + "\n" + body)
}

func (m ResultListModel) visibleResultRows() int {
	// One for title, two for borders
	return m.height - 3
}
