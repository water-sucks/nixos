package cmdUtils

import (
	"fmt"
	"os"
	"strings"

	"github.com/fatih/color"
)

func ConfirmationInput(msg string) (bool, error) {
	var input string

	fmt.Fprintf(os.Stderr, "%s\n[y/n]: ", color.GreenString("|> %s", msg))

	_, err := fmt.Scanln(&input)
	if err != nil {
		return false, err
	}

	if len(input) == 0 {
		return false, err
	}

	input = strings.ToLower(strings.TrimSpace(input))

	return input[0] == 'y', nil
}
