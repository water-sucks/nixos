package logger

import (
	"log"
	"os"

	"github.com/fatih/color"
	"github.com/water-sucks/nixos/internal/utils"
)

type Logger struct {
	print *log.Logger
	info  *log.Logger
	warn  *log.Logger
	error *log.Logger

	level        LogLevel
	stepNumber   uint
	stepsEnabled bool
}

type LogLevel int

const (
	LogLevelInfo   LogLevel = 0
	LogLevelWarn   LogLevel = 1
	LogLevelError  LogLevel = 2
	LogLevelSilent LogLevel = 3
)

func NewLogger() *Logger {
	green := color.New(color.FgGreen)
	boldYellow := color.New(color.FgYellow).Add(color.Bold)
	boldRed := color.New(color.FgRed).Add(color.Bold)

	return &Logger{
		print:      log.New(os.Stderr, "", 0),
		info:       log.New(os.Stderr, green.Sprint("info: "), 0),
		warn:       log.New(os.Stderr, boldYellow.Sprint("warning: "), 0),
		error:      log.New(os.Stderr, boldRed.Sprint("error: "), 0),
		stepNumber: 0,
		// Some commands call other subcommands through forks, such.
		// as `install` calling `enter`. For those, step numbers can
		// be confusing.
		stepsEnabled: os.Getenv("NIXOS_CLI_DISABLE_STEPS") == "",
	}
}

func (l *Logger) Print(v ...any) {
	l.print.Print(v...)
}

func (l *Logger) Printf(format string, v ...any) {
	l.print.Printf(format, v...)
}

func (l *Logger) Info(v ...any) {
	if l.level > LogLevelInfo {
		return
	}
	l.info.Println(v...)
}

func (l *Logger) Infof(format string, v ...any) {
	if l.level > LogLevelInfo {
		return
	}
	l.info.Printf(format+"\n", v...)
}

func (l *Logger) Warn(v ...any) {
	if l.level > LogLevelWarn {
		return
	}
	l.warn.Println(v...)
}

func (l *Logger) Warnf(format string, v ...any) {
	if l.level > LogLevelWarn {
		return
	}
	l.warn.Printf(format+"\n", v...)
}

func (l *Logger) Error(v ...any) {
	if l.level > LogLevelError {
		return
	}
	l.error.Println(v...)
}

func (l *Logger) Errorf(format string, v ...any) {
	if l.level > LogLevelError {
		return
	}
	l.error.Printf(format+"\n", v...)
}

func (l *Logger) CmdArray(argv []string) {
	if l.level > LogLevelInfo {
		return
	}

	msg := color.New(color.FgBlue).Sprintf("$ %v", utils.EscapeAndJoinArgs(argv))
	l.print.Printf("%v\n", msg)
}

func (l *Logger) Step(message string) {
	// Replace step numbers with generic l.Info() calls if
	// steps are disabled, to increase clarity in steps.
	if !l.stepsEnabled {
		l.Info(message)
		return
	}

	if l.level > LogLevelInfo {
		return
	}

	l.stepNumber++
	if l.stepNumber > 1 {
		l.print.Println()
	}
	msg := color.New(color.FgMagenta).Add(color.Bold).Sprintf("%v. %v", l.stepNumber, message)
	l.print.Println(msg)
}

func (l *Logger) SetLogLevel(level LogLevel) {
	l.level = level
}

// Call this when the colors have been enabled or disabled.
func (l *Logger) RefreshColorPrefixes() {
	green := color.New(color.FgGreen)
	boldYellow := color.New(color.FgYellow).Add(color.Bold)
	boldRed := color.New(color.FgRed).Add(color.Bold)

	l.info.SetPrefix(green.Sprint("info: "))
	l.warn.SetPrefix(boldYellow.Sprint("warning: "))
	l.error.SetPrefix(boldRed.Sprint("error: "))
}
