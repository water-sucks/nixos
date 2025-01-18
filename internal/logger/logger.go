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

	stepNumber uint
}

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
	}
}

func (l *Logger) Print(v ...interface{}) {
	l.print.Print(v...)
}

func (l *Logger) Printf(format string, v ...interface{}) {
	l.print.Printf(format, v...)
}

func (l *Logger) Info(v ...interface{}) {
	l.info.Println(v...)
}

func (l *Logger) Infof(format string, v ...interface{}) {
	l.info.Printf(format+"\n", v...)
}

func (l *Logger) Warn(v ...interface{}) {
	l.warn.Println(v...)
}

func (l *Logger) Warnf(format string, v ...interface{}) {
	l.warn.Printf(format+"\n", v...)
}

func (l *Logger) Error(v ...interface{}) {
	l.error.Println(v...)
}

func (l *Logger) Errorf(format string, v ...interface{}) {
	l.error.Printf(format+"\n", v...)
}

func (l *Logger) CmdArray(argv []string) {
	msg := color.New(color.FgBlue).Sprintf("$ %v", utils.EscapeAndJoinArgs(argv))
	l.print.Printf("%v\n", msg)
}

func (l *Logger) Step(message string) {
	l.stepNumber++
	if l.stepNumber > 1 {
		l.print.Println()
	}
	msg := color.New(color.FgMagenta).Add(color.Bold).Sprintf("%v. %v", l.stepNumber, message)
	l.print.Println(msg)
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
