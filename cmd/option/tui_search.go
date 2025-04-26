package option

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type SearchBarModel struct {
	input        textinput.Model
	debouncer    Debouncer
	debounceTime int64

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

	debouncer := Debouncer{}

	return SearchBarModel{
		input:        ti,
		debouncer:    debouncer,
		debounceTime: 25,
		totalCount:   totalCount,
	}
}

func (m SearchBarModel) Update(msg tea.Msg) (SearchBarModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		oldValue := m.input.Value()
		input, cmd := m.input.Update(msg)
		m.input = input

		if oldValue != m.input.Value() {
			delay := time.Duration(m.debounceTime) * time.Millisecond
			cmd := m.debouncer.Tick(delay, func() tea.Msg {
				return searchChangedMsg(m.input.Value())
			})
			return m, cmd
		}

		return m, cmd

	case DebounceMsg:
		if msg.ID != m.debouncer.ID {
			// Explicitly return the model early here, since this
			// is a stale debounce command; there's no need to rebuild
			// the UI off this message.
			return m, nil
		}

		switch inner := msg.Msg.(type) {
		case searchChangedMsg:
			return m, func() tea.Msg {
				return RunSearchMsg{Query: string(inner)}
			}
		}
	}

	return m, nil
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

type Debouncer struct {
	ID int
}

func (d *Debouncer) Tick(dur time.Duration, msg func() tea.Msg) tea.Cmd {
	d.ID++
	newDebounceID := d.ID

	return tea.Tick(dur, func(time.Time) tea.Msg {
		return DebounceMsg{
			ID:  newDebounceID,
			Msg: msg(),
		}
	})
}

type DebounceMsg struct {
	ID  int
	Msg tea.Msg
}

type searchChangedMsg string
