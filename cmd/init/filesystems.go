package init

import (
	"bytes"
	"os"
	"strings"

	"github.com/water-sucks/nixos/internal/logger"
	"github.com/water-sucks/nixos/internal/system"
)

func lvmDevicesExist(s system.CommandRunner, log *logger.Logger) bool {
	cmd := system.NewCommand("lsblk", "-o", "")

	var stdout bytes.Buffer
	cmd.Stdout = &stdout

	_, err := s.Run(cmd)
	if err != nil {
		log.Warnf("failed to run lsblk: %v", err)
		return false
	}

	// There should probably be a better metric than just checking if the
	// string "lvm" exists inside `lsblk` output, but meh. This is a rough
	// heuristic that somewhat works unless device labels end up having "lvm"
	// in them.
	return strings.Contains(stdout.String(), "lvm")
}

func bcachefsFilesystemsExist(log *logger.Logger) bool {
	entries, err := os.ReadDir("/dev")
	if err != nil {
		log.Warnf("failed to read /dev: %v", err)
		return false
	}

	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), "bcache") {
			return true
		}
	}

	return false
}
