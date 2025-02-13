package init

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"

	"github.com/water-sucks/nixos/internal/logger"
	"github.com/water-sucks/nixos/internal/system"
)

const (
	swapDeviceListFilename = "/proc/swaps"
)

type SwapDevice struct{}

func findSwapDevices(log *logger.Logger) []string {
	swapDevices := []string{}

	swapDeviceList, err := os.Open(swapDeviceListFilename)
	if err != nil {
		log.Warnf("failed to open swap device list %v: %v", swapDeviceListFilename, err)
		return swapDevices
	}
	defer swapDeviceList.Close()

	s := bufio.NewScanner(swapDeviceList)
	s.Split(bufio.ScanLines)

	_ = s.Scan() // Skip header line

	for s.Scan() {
		fields := strings.Fields(s.Text())
		swapFilename := fields[0]
		swapType := fields[1]

		if swapType == "partition" {
			swapDevices = append(swapDevices, findStableDevPath(swapFilename))
		} else if swapType == "file" {
			log.Infof("skipping swap file %v, specify in configuration manually if needed", swapFilename)
		} else {
			log.Warnf("unsupported swap type %v for %v; do not specify in configuration", swapType, swapFilename)
		}
	}

	return swapDevices
}

func lvmDevicesExist(s system.CommandRunner, log *logger.Logger) bool {
	cmd := system.NewCommand("lsblk", "-o", "TYPE")

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

func findStableDevPath(devicePath string) string {
	if !filepath.IsAbs(devicePath) {
		return devicePath
	}

	rdev, err := getRdev(devicePath)
	if err != nil {
		return devicePath
	}

	directoriesToCheck := []string{
		"/dev/disk/by-uuid",
		"/dev/mapper",
		"/dev/disk/by-label",
	}

	for _, directory := range directoriesToCheck {
		if stablePath, ok := checkDirForEqualDevice(rdev, directory); ok {
			return stablePath
		}
	}

	return devicePath
}

func getRdev(devicePath string) (uint64, error) {
	stat, err := os.Stat(devicePath)
	if err != nil {
		return 0, err
	}
	sysStat := stat.Sys()
	if sysStat == nil {
		return 0, err
	}
	devStat, ok := sysStat.(*syscall.Stat_t)
	if !ok {
		return 0, err
	}

	return devStat.Rdev, nil
}

func checkDirForEqualDevice(deviceRdev uint64, dirname string) (string, bool) {
	entries, err := os.ReadDir(dirname)
	if err != nil {
		return "", false
	}

	for _, entry := range entries {
		devicePath := filepath.Join(dirname, entry.Name())
		fmt.Println("checking device path", devicePath)
		rdev, err := getRdev(devicePath)
		if err != nil {
			continue
		}

		if rdev == deviceRdev {
			return devicePath, true
		}
	}

	return "", false
}
