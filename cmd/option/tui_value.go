package option

import (
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/fatih/color"
	"github.com/muesli/termenv"
	"github.com/nix-community/nixos-cli/internal/configuration"
)

type EvalValueModel struct {
	vp      viewport.Model
	spinner spinner.Model

	cfg    configuration.Configuration
	option string

	loading   bool
	evaluated string
	evalErr   error

	width  int
	height int
}

var spinnerStyle = lipgloss.NewStyle().Foreground(lipgloss.ANSIColor(termenv.ANSIBlue))

func NewEvalValueModel(cfg configuration.Configuration) EvalValueModel {
	vp := viewport.New(0, 0)
	vp.SetHorizontalStep(1)
	vp.Style = focusedBorderStyle

	sp := spinner.New()
	sp.Spinner = spinner.Line
	sp.Style = spinnerStyle

	return EvalValueModel{
		vp:      vp,
		cfg:     cfg,
		spinner: sp,
		loading: false,
	}
}

type EvalValueStartMsg struct {
	Option string
}

type EvalValueFinishedMsg struct {
	Value string
	Err   error
}

func (m EvalValueModel) Update(msg tea.Msg) (EvalValueModel, tea.Cmd) {
	var cmds []tea.Cmd

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

		return m, nil

	case EvalValueStartMsg:
		if m.option == msg.Option {
			break
		}

		m.option = msg.Option
		m.loading = true
		m.evaluated = ""
		m.evalErr = nil

		cmds = append(cmds, m.evalOptionCmd())
		cmds = append(cmds, m.spinner.Tick)

	case EvalValueFinishedMsg:
		m.loading = false
		m.evaluated = msg.Value
		m.evalErr = msg.Err

		m.vp.SetContent(m.constructValueContent())
	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		cmds = append(cmds, cmd)
	}

	if m.loading {
		m.vp.SetContent(m.constructLoadingContent())
	}

	var vpCmd tea.Cmd
	m.vp, vpCmd = m.vp.Update(msg)
	cmds = append(cmds, vpCmd)

	return m, tea.Batch(cmds...)
}

func (m EvalValueModel) evalOptionCmd() tea.Cmd {
	return func() tea.Msg {
		value, err := m.cfg.EvalAttribute(m.option)
		if value == nil || err != nil {
			return EvalValueFinishedMsg{Value: "", Err: err}
		}
		return EvalValueFinishedMsg{Value: *value, Err: err}
	}
}

func (m EvalValueModel) SetOption(o string) (EvalValueModel, tea.Cmd) {
	if o == m.option {
		return m, nil
	}

	m.option = o
	m.loading = true
	m.evaluated = ""
	m.evalErr = nil

	evalCmd := func() tea.Msg {
		value, err := m.cfg.EvalAttribute(m.option)
		return EvalValueFinishedMsg{Value: *value, Err: err}
	}

	return m, evalCmd
}

func (m EvalValueModel) View() string {
	return m.vp.View()
}

var (
	evalSuccessColor = color.New(color.FgWhite)
	evalErrorColor   = color.New(color.FgRed).Add(color.Bold)
)

func (m EvalValueModel) constructLoadingContent() string {
	title := lipgloss.PlaceHorizontal(m.width, lipgloss.Left, titleStyle.Render(m.option))
	line := lipgloss.NewStyle().Width(m.width).Inherit(titleRuleStyle).Render("")
	body := "Evaluating attribute..." + m.spinner.View()

	return title + "\n" + line + "\n" + body
}

func (m EvalValueModel) constructValueContent() string {
	title := lipgloss.PlaceHorizontal(m.width, lipgloss.Left, titleStyle.Render(m.option))
	line := lipgloss.NewStyle().Width(m.width).Inherit(titleRuleStyle).Render("")

	body := ""

	err := m.evalErr
	if err != nil {
		errStr := err.Error()
		if e, ok := err.(*configuration.AttributeEvaluationError); ok {
			errStr += "\n\nevaluation trace:\n-----------------\n" + e.EvaluationOutput
		}

		body = evalErrorColor.Sprint(errStr)
	} else {
		body = evalSuccessColor.Sprint(m.evaluated)
	}

	return title + "\n" + line + "\n" + body
}
