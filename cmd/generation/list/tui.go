package list

import (
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/termenv"
	"github.com/water-sucks/nixos/internal/generation"
)

var (
	// Colors
	ansiRed     = lipgloss.ANSIColor(termenv.ANSIRed)
	ansiYellow  = lipgloss.ANSIColor(termenv.ANSIYellow)
	ansiGreen   = lipgloss.ANSIColor(termenv.ANSIGreen)
	ansiWhite   = lipgloss.ANSIColor(termenv.ANSIBrightWhite)
	ansiBlue    = lipgloss.ANSIColor(termenv.ANSIBlue)
	ansiCyan    = lipgloss.ANSIColor(termenv.ANSICyan)
	ansiMagenta = lipgloss.ANSIColor(termenv.ANSIMagenta)

	// Styles
	itemStyle         = lipgloss.NewStyle().MarginLeft(4).PaddingLeft(1).Border(lipgloss.NormalBorder(), false, false, false, true)
	currentItemStyle  = lipgloss.NewStyle().MarginLeft(4).PaddingLeft(1).Foreground(ansiGreen).Border(lipgloss.NormalBorder(), false, false, false, true).BorderForeground(ansiGreen)
	selectedItemStyle = lipgloss.NewStyle().MarginLeft(4).PaddingLeft(1).Foreground(ansiYellow).Border(lipgloss.NormalBorder(), false, false, false, true).BorderForeground(ansiYellow)
	attrStyle         = lipgloss.NewStyle().Foreground(ansiCyan)
	boldStyle         = lipgloss.NewStyle().Bold(true)
	italicStyle       = lipgloss.NewStyle().Italic(true)
)

type generationItem struct {
	Generation generation.Generation
	Selected   bool
}

func (i generationItem) FilterValue() string {
	g := i.Generation
	return fmt.Sprintf("%v %v", g.Number, g.Description)
}

type generationItemDelegate struct{}

func (d generationItemDelegate) Height() int { return 6 }

func (d generationItemDelegate) Spacing() int { return 1 }

func (d generationItemDelegate) Update(_ tea.Msg, _ *list.Model) tea.Cmd { return nil }

func (d generationItemDelegate) Render(w io.Writer, m list.Model, index int, listItem list.Item) {
	i, ok := listItem.(generationItem)
	if !ok {
		return
	}

	g := i.Generation

	current := ""
	if g.IsCurrent {
		current = " (active)"
	}

	str := boldStyle.Render(fmt.Sprintf("%v%v", g.Number, current))
	if len(g.Description) > 0 {
		str += italicStyle.Render(fmt.Sprintf(" - %v", g.Description))
	}

	cfgRev := g.ConfigurationRevision
	if cfgRev == "" {
		cfgRev = italicStyle.Render("(unknown)")
	}

	nixpkgsRev := g.NixpkgsRevision
	if nixpkgsRev == "" {
		nixpkgsRev = italicStyle.Render("(unknown)")
	}

	kernelVersion := g.KernelVersion
	if kernelVersion == "" {
		kernelVersion = italicStyle.Render("(unknown)")
	}

	var specialisations string
	if len(g.Specialisations) > 0 {
		specialisations = strings.Join(g.Specialisations, ", ")
	} else {
		specialisations = italicStyle.Render("(none)")
	}

	str += fmt.Sprintf("\n%s    :: %s", attrStyle.Render("NixOS Version"), g.NixosVersion)
	str += fmt.Sprintf("\n%s    :: %s", attrStyle.Render("Creation Date"), g.CreationDate.Format(time.ANSIC))
	str += fmt.Sprintf("\n%s :: %s", attrStyle.Render("Nixpkgs Revision"), nixpkgsRev)
	str += fmt.Sprintf("\n%s  :: %s", attrStyle.Render("Config Revision"), cfgRev)
	str += fmt.Sprintf("\n%s   :: %s", attrStyle.Render("Kernel Version"), kernelVersion)
	str += fmt.Sprintf("\n%s  :: %s", attrStyle.Render("Specialisations"), specialisations)

	fn := itemStyle.Render

	if index == m.Index() {
		fn = func(s ...string) string {
			return currentItemStyle.Render(strings.Join(s, " "))
		}
	} else if i.Selected {
		fn = func(s ...string) string {
			return selectedItemStyle.Render(strings.Join(s, " "))
		}
	}

	fmt.Fprint(w, fn(str))
}

type model struct {
	list     list.Model
	quitting bool
}

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.list.SetWidth(msg.Width)
		m.list.SetHeight(msg.Height - 1)
		return m, nil

	case tea.KeyMsg:
		if m.list.FilterState() == list.Filtering {
			break
		}

		switch keypress := msg.String(); keypress {
		case "q", "ctrl+c":
			m.quitting = true
			return m, tea.Quit

		case tea.KeySpace.String():
			g := m.list.SelectedItem().(generationItem)
			g.Selected = !g.Selected
			m.list.SetItem(m.list.Index(), g)
		}
	}

	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)
	return m, cmd
}

func (m model) View() string {
	// Clear the view before exiting.
	if m.quitting {
		return ""
	}

	return "\n" + m.list.View()
}

func generationUI(generations []generation.Generation) error {
	items := make([]list.Item, len(generations))
	for i, v := range generations {
		items[i] = generationItem{
			Generation: v,
			Selected:   false,
		}
	}

	l := list.New(items, generationItemDelegate{}, 0, 0)

	l.Title = "NixOS Generations"

	l.Styles.Title = lipgloss.NewStyle().MarginLeft(2).Background(ansiRed).Foreground(ansiWhite)
	l.Styles.PaginationStyle = list.DefaultStyles().PaginationStyle.PaddingLeft(4)
	l.Styles.HelpStyle = list.DefaultStyles().HelpStyle.PaddingLeft(4).PaddingBottom(1)
	l.Styles.StatusBar = lipgloss.NewStyle().PaddingLeft(4).PaddingBottom(1).Foreground(ansiMagenta)

	l.FilterInput.PromptStyle = lipgloss.NewStyle().Foreground(ansiBlue).Bold(true).PaddingLeft(2)
	l.FilterInput.TextStyle = lipgloss.NewStyle().Foreground(ansiBlue)
	l.FilterInput.Cursor.Style = lipgloss.NewStyle().Foreground(ansiBlue)
	l.Styles.StatusBarActiveFilter = lipgloss.NewStyle().Foreground(ansiBlue)
	l.Styles.StatusBarFilterCount = lipgloss.NewStyle().Foreground(ansiBlue)

	l.AdditionalFullHelpKeys = func() []key.Binding {
		return []key.Binding{
			key.NewBinding(
				key.WithKeys("space"),
				key.WithHelp("space", "select for deletion"),
			),
			key.NewBinding(
				key.WithKeys("enter"),
				key.WithHelp("enter", "switch to generation"),
			),
			key.NewBinding(
				key.WithKeys("d"),
				key.WithHelp("d", "delete selected generations"),
			),
		}
	}

	m := model{list: l}

	if _, err := tea.NewProgram(m).Run(); err != nil {
		return err
	}

	return nil
}
