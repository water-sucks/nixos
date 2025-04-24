package option

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type SearchBarModel struct {
	input   textinput.Model
	width   int
	height  int
	focused bool

	resultCount int
	totalCount  int
}

func NewSearchBarModel(totalCount int) SearchBarModel {
	ti := textinput.New()
	ti.Placeholder = "Search for options..."
	ti.Prompt = "> "

	return SearchBarModel{
		input:      ti,
		totalCount: totalCount,
	}
}

func (m SearchBarModel) Update(msg tea.Msg) (SearchBarModel, tea.Cmd) {
	var cmd tea.Cmd
	m.input, cmd = m.input.Update(msg)
	return m, cmd
}

func (m SearchBarModel) SetFocused(focused bool) SearchBarModel {
	m.focused = focused

	if focused {
		m.input.Focus()
	} else {
		m.input.Blur()
	}
	return m
}

func (m SearchBarModel) SetWidth(width int) SearchBarModel {
	m.width = width
	m.input.Width = width

	return m
}

func (m SearchBarModel) SetHeight(height int) SearchBarModel {
	m.height = height
	return m
}

func (m SearchBarModel) SetResultCount(count int) SearchBarModel {
	m.resultCount = count
	return m
}

func (m SearchBarModel) Value() string {
	return m.input.Value()
}

func (m SearchBarModel) View() string {
	left := m.input.View()
	right := m.resultCountStr()

	rightWidth := lipgloss.Width(right)
	spaceBetween := 1

	maxLeftWidth := max(m.width-rightWidth-spaceBetween, 0)
	leftWidth := lipgloss.Width(left)
	if leftWidth > maxLeftWidth {
		left = truncateString(left, maxLeftWidth)
	}

	padding := m.width - lipgloss.Width(left) - rightWidth

	style := inactiveBorderStyle
	if m.focused {
		style = focusedBorderStyle
	}

	return style.Width(m.width).Render(left + strings.Repeat(" ", padding) + right)
}

func (m SearchBarModel) resultCountStr() string {
	if m.input.Value() != "" {
		return fmt.Sprintf("%d/%d", m.resultCount, m.totalCount)
	}

	return ""
}

func truncateString(s string, width int) string {
	runes := []rune(s)
	if len(runes) <= width {
		return s
	}
	return string(runes[:width])
}
