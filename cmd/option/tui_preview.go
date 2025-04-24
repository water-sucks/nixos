package option

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/fatih/color"
	"github.com/water-sucks/nixos/internal/option"
)

type PreviewModel struct {
	vp viewport.Model

	option *option.NixosOption

	focused  bool
	prettify bool

	lastRendered *option.NixosOption
}

func NewPreviewModel(prettify bool) PreviewModel {
	vp := viewport.New(0, 0)

	return PreviewModel{
		prettify: prettify,
		vp:       vp,
	}
}

func (m PreviewModel) SetHeight(height int) PreviewModel {
	m.vp.Height = height
	return m
}

func (m PreviewModel) SetWidth(width int) PreviewModel {
	m.vp.Width = width
	return m
}

func (m PreviewModel) SetFocused(focus bool) PreviewModel {
	m.focused = focus
	return m
}

func (m PreviewModel) SetOption(opt *option.NixosOption) PreviewModel {
	m.option = opt
	return m
}

func (m PreviewModel) ScrollUp() PreviewModel {
	m.vp.ScrollUp(1)
	return m
}

func (m PreviewModel) ScrollDown() PreviewModel {
	m.vp.ScrollDown(1)
	return m
}

var (
	titleColor  = color.New(color.Bold)
	italicColor = color.New(color.Italic)
)

func (m PreviewModel) Update(msg tea.Msg) (PreviewModel, tea.Cmd) {
	var cmd tea.Cmd
	if m.focused {
		m.vp, cmd = m.vp.Update(msg)
	}

	o := m.option

	// Do not re-render options if it has already been rendered before.
	// Setting content will reset the scroll counter, and rendering
	// an option is expensive.
	if o == m.lastRendered && o != nil {
		return m, cmd
	}

	m.vp.SetContent(m.renderOptionView())
	m.vp.GotoTop()

	m.lastRendered = o

	return m, cmd
}

func (m PreviewModel) ForceContentUpdate() PreviewModel {
	m.vp.SetContent(m.renderOptionView())
	m.vp.GotoTop()

	return m
}

func (m PreviewModel) renderOptionView() string {
	o := m.option

	sb := strings.Builder{}

	title := lipgloss.PlaceHorizontal(m.vp.Width, lipgloss.Center, titleColor.Sprint("Option Preview"))
	sb.WriteString(title)
	sb.WriteString("\n\n")

	if m.option == nil {
		sb.WriteString("No option selected.")
		return sb.String()
	}

	desc := strings.TrimSpace(stripInlineCodeAnnotations(o.Description))
	if desc == "" {
		desc = italicColor.Sprint("(none)")
	} else {
		if m.prettify {
			r := markdownRenderer()
			d, err := r.Render(desc)
			if err != nil {
				desc = italicColor.Sprintf("warning: failed to render description: %v\n", err) + desc
			} else {
				desc = strings.TrimSpace(d)
			}
		}
	}

	var defaultText string
	if o.Default != nil {
		defaultText = color.WhiteString(strings.TrimSpace(o.Default.Text))
	} else {
		defaultText = italicColor.Sprint("(none)")
	}

	exampleText := ""
	if o.Example != nil {
		exampleText = color.WhiteString(strings.TrimSpace(o.Example.Text))
	}

	sb.WriteString(fmt.Sprintf("%v\n%v\n\n", titleColor.Sprint("Name"), o.Name))
	sb.WriteString(fmt.Sprintf("%v\n%v\n\n", titleColor.Sprint("Description"), desc))
	sb.WriteString(fmt.Sprintf("%v\n%v\n\n", titleColor.Sprint("Type"), italicColor.Sprint(o.Type)))
	sb.WriteString(fmt.Sprintf("%v\n%v\n\n", titleColor.Sprint("Default"), defaultText))
	if exampleText != "" {
		sb.WriteString(fmt.Sprintf("%v\n%v\n\n", titleColor.Sprint("Example"), exampleText))
	}

	if len(o.Declarations) > 0 {
		sb.WriteString(fmt.Sprintf("%v\n", titleColor.Sprint("Declared In")))
		for _, v := range o.Declarations {
			sb.WriteString(fmt.Sprintf("  - %v\n", italicColor.Sprint(v)))
		}
	}

	sb.WriteString(fmt.Sprintf("\n%v\n", color.YellowString("This option is read-only.")))

	return sb.String()
}

func (m PreviewModel) View() string {
	if m.focused {
		m.vp.Style = focusedBorderStyle
	} else {
		m.vp.Style = inactiveBorderStyle
	}

	return m.vp.View()
}
