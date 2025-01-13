package logger

import (
	"log"
	"os"

	"github.com/fatih/color"

	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
)

type Logger struct {
	print *log.Logger
	info  *log.Logger
	warn  *log.Logger
	error *log.Logger
}

func NewLogger() *Logger {
	return &Logger{
		print: log.New(os.Stderr, "", 0),
		info:  log.New(os.Stderr, color.GreenString("info: "), 0),
		warn:  log.New(os.Stderr, color.YellowString("warning: "), 0),
		error: log.New(os.Stderr, color.RedString("error: "), 0),
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
	l.print.Printf("$ %v\n", cmdUtils.EscapeAndJoinArgs(argv))
}

// Call this when the colors have been enabled or disabled.
func (l *Logger) RefreshColorPrefixes() {
	l.info.SetPrefix(color.GreenString("info: "))
	l.warn.SetPrefix(color.YellowString("warning: "))
	l.error.SetPrefix(color.RedString("error: "))
}
