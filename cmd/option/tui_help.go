package option

import (
	_ "embed"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

//go:embed option_help.md
var helpContent string

func init() {
	r := markdownRenderer()
	rendered, err := r.Render(helpContent)
	if err == nil {
		helpContent = rendered
	}
}

type HelpModel struct {
	vp viewport.Model

	width  int
	height int
}

func NewHelpModel() HelpModel {
	vp := viewport.New(0, 0)
	vp.SetHorizontalStep(1)

	vp.Style = focusedBorderStyle

	return HelpModel{
		vp: vp,
	}
}

func (m HelpModel) Update(msg tea.Msg) (HelpModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "esc":
			return m, func() tea.Msg {
				return ChangeViewModeMsg(ViewModeSearch)
			}
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width - 4
		m.height = msg.Height - 4

		m.vp.Width = m.width
		m.vp.Height = m.height

		m.vp.SetContent(m.constructHelpContent())
		return m, nil
	}

	var cmd tea.Cmd
	m.vp, cmd = m.vp.Update(msg)

	return m, cmd
}

func (m HelpModel) View() string {
	return m.vp.View()
}

func (m HelpModel) constructHelpContent() string {
	title := lipgloss.PlaceHorizontal(m.width, lipgloss.Center, titleStyle.Render("Help"))
	line := lipgloss.NewStyle().Width(m.width).Inherit(titleRuleStyle).Render("")

	return title + "\n" + line + helpContent
}
