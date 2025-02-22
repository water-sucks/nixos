package enter

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"

	"github.com/spf13/cobra"

	cmdTypes "github.com/water-sucks/nixos/internal/cmd/types"
	cmdUtils "github.com/water-sucks/nixos/internal/cmd/utils"
	"github.com/water-sucks/nixos/internal/constants"
	"github.com/water-sucks/nixos/internal/logger"
	"github.com/water-sucks/nixos/internal/settings"
	"github.com/water-sucks/nixos/internal/system"
)

func EnterCommand() *cobra.Command {
	opts := cmdTypes.EnterOpts{}

	cmd := cobra.Command{
		Use:   "enter [flags] [-- ARGS...]",
		Short: "Chroot into a NixOS installation",
		Long:  "Enter a NixOS chroot environment.",
		PreRunE: func(cmd *cobra.Command, args []string) error {
			if len(args) > 0 {
				opts.CommandArray = args
			}

			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			return cmdUtils.CommandErrorHandler(enterMain(cmd, &opts))
		},
	}

	cmd.Flags().StringVarP(&opts.Command, "command", "c", "", "Command `string` to execute in bash")
	cmd.Flags().StringVarP(&opts.RootLocation, "root", "r", "/mnt", "NixOS system root `path` to enter")
	cmd.Flags().StringVar(&opts.System, "system", "", "NixOS system configuration to activate at `path`")
	cmd.Flags().BoolVarP(&opts.Silent, "silent", "s", false, "Suppress all system activation output")
	cmd.Flags().BoolVarP(&opts.Verbose, "verbose", "v", false, "Show verbose logging")

	cmd.MarkFlagsMutuallyExclusive("silent", "verbose")

	cmdUtils.SetHelpFlagText(&cmd)
	cmd.SetHelpTemplate(cmd.HelpTemplate() + `
Arguments:
  [ARGS...]  Interpret arguments as the command to run directly

If providing a command through positional arguments with flags, a preceding
double dash (--) is required. Otherwise, unexpected behavior may occur.
`)

	return &cmd
}

func enterMain(cmd *cobra.Command, opts *cmdTypes.EnterOpts) error {
	log := logger.FromContext(cmd.Context())
	cfg := settings.FromContext(cmd.Context())

	nixosMarker := filepath.Join(opts.RootLocation, constants.NixOSMarker)
	if _, err := os.Stat(nixosMarker); err != nil {
		log.Errorf("%v is not a valid NixOS system", opts.RootLocation)
	}

	isReexec := os.Getenv(NIXOS_REEXEC) == "1"
	if !isReexec {
		err := execSandboxedEnterProcess(log, opts.Verbose)
		if err != nil {
			log.Errorf("failed to exec sandboxed process with unshare: %v", err)
		}
		return err
	}

	if opts.Verbose {
		log.Info("sandboxed process successfully")
		log.Print()
	}

	log.Step("Bind-mounting resources...")
	log.Info("remounting root privately for namespace")

	err := syscall.Mount("/", "/", "", syscall.MS_REMOUNT|syscall.MS_PRIVATE|syscall.MS_REC, "")
	if err != nil {
		log.Errorf("failed to remount root: %v", err)
		return err
	}

	log.Infof("bind-mounting /dev to %v", opts.RootLocation)
	err = bindMountDirectory(opts.RootLocation, "/dev")
	if err != nil {
		log.Errorf("failed to bind-mount /dev: %v", err)
		return err
	}

	log.Infof("bind-mounting /proc to %v", opts.RootLocation)
	err = bindMountDirectory(opts.RootLocation, "/proc")
	if err != nil {
		log.Errorf("failed to bind-mount /proc: %v", err)
		return err
	}

	var resolvConfErr error
	if cfg.Enter.MountResolvConf {
		if _, err := os.Stat("/etc/resolv.conf"); err == nil {
			log.Infof("bind-mounting /etc/resolv.conf to %v for Internet access", opts.RootLocation)

			targetResolvConf, err := findResolvConfLocation(opts.RootLocation)
			if err != nil {
				log.Warnf("failed to find resolv.conf location: %v", err)
				resolvConfErr = err
				goto resolvConfDone
			}

			err = syscall.Mount("/etc/resolv.conf", targetResolvConf, "", syscall.MS_BIND, "")
			if err != nil {
				log.Warnf("failed to bind-mount /etc/resolv.conf: %v", err)
				resolvConfErr = err
				goto resolvConfDone
			}
		} else {
			log.Warnf("/etc/resolv.conf does not exist, skipping mounting", err)
		}
	}

resolvConfDone:
	if resolvConfErr != nil {
		log.Warnf("Internet access may not be available", err)
	}

	systemClosure := opts.System
	if systemClosure == "" {
		systemClosure = filepath.Join(constants.NixProfileDirectory, "system")
	}

	s := system.NewLocalSystem()

	log.Step("Activating system...")

	err = activate(s, log, opts.RootLocation, systemClosure, opts.Verbose, opts.Silent)
	if err != nil {
		log.Errorf("failed to activate system: %v", err)
		return err
	}

	log.Step("Starting chroot...")

	if len(opts.CommandArray) > 0 && len(opts.Command) > 1 {
		log.Warn("preferring --command flag over positional args, both were specified")
	}

	bash := filepath.Join(systemClosure, "sw", "bin", "bash")
	args := opts.CommandArray
	if opts.Command != "" {
		args = []string{bash, "-c", opts.Command}
	}
	if len(args) == 0 {
		args = []string{bash, "--login"}
	}

	err = startChroot(s, log, opts.RootLocation, args, opts.Verbose)
	if err != nil {
		log.Errorf("failed to start chroot: %v", err)
		return err
	}

	return nil
}

const NIXOS_REEXEC = "_NIXOS_ENTER_REEXEC"

func execSandboxedEnterProcess(log *logger.Logger, verbose bool) error {
	if verbose {
		log.Infof("sandboxing process with unshare")
	}

	argv := []string{"unshare", "--fork", "--mount", "--uts", "--mount-proc", "--pid"}
	argv = append(argv, os.Args...)

	// Map root user if not running as root
	if os.Geteuid() != 0 {
		argv = append(argv, "-r")
	}

	env := os.Environ()
	env = append(env, NIXOS_REEXEC+"=1")

	if verbose {
		log.CmdArray(argv)
	}

	unsharePath, err := exec.LookPath(argv[0])
	if err != nil {
		return err
	}

	err = syscall.Exec(unsharePath, argv, env)
	return err
}

func bindMountDirectory(root string, target string) error {
	targetDirname := filepath.Join(root, target)

	err := os.MkdirAll(targetDirname, 0o755)
	if err != nil {
		if !os.IsExist(err) {
			return err
		}
	}

	err = syscall.Mount(root, target, "", syscall.MS_BIND, "")
	return err
}

func findResolvConfLocation(root string) (string, error) {
	targetResolvConf := filepath.Join(root, "/etc/resolv.conf")

	resolvConf, err := os.OpenFile(targetResolvConf, os.O_CREATE|os.O_RDONLY, 0o644)
	if err != nil {
		return "", err
	}
	resolvConf.Close()

	resolvedLocation, err := filepath.EvalSymlinks(targetResolvConf)
	if err != nil {
		return "", err
	}

	var finalLocation string
	if !strings.HasPrefix(resolvedLocation, "/") {
		finalLocation = filepath.Join(root, resolvedLocation)
	} else {
		finalLocation = filepath.Join(root, "etc", resolvedLocation)
	}

	return finalLocation, nil
}

func activate(s system.CommandRunner, log *logger.Logger, root string, systemClosure string, verbose bool, silent bool) error {
	localeArchive := filepath.Join(systemClosure, "sw", "lib", "locale", "locale-archive")
	activateScript := filepath.Join(systemClosure, "activate")

	argv := []string{"chroot", root, activateScript}

	if verbose {
		log.CmdArray(argv)
	}

	// Run the activation script.
	activateCmd := system.NewCommand(argv[0], argv[1:]...)
	activateCmd.SetEnv("LOCALE_ARCHIVE", localeArchive)
	activateCmd.SetEnv("IN_NIXOS_ENTER", "1")

	if silent {
		activateCmd.Stdout = nil
		activateCmd.Stderr = nil
	}

	_, err := s.Run(activateCmd)
	if err != nil {
		return err
	}

	// Create a tmpfs for building/activating the NixOS system.
	systemdTmpfiles := filepath.Join(systemClosure, "sw", "bin", "systemd-tmpfiles")
	argv = []string{"chroot", root, systemdTmpfiles, "--create", "--remove", "-E"}

	if verbose {
		log.CmdArray(argv)
	}

	tmpfilesCmd := system.NewCommand(argv[0], argv[1:]...)

	// Hide the unhelpful "failed to replace specifiers" errors caused by missing /etc/machine-id.
	tmpfilesCmd.Stdout = nil
	tmpfilesCmd.Stderr = nil

	_, err = s.Run(tmpfilesCmd)
	return err
}

func startChroot(s system.CommandRunner, log *logger.Logger, root string, args []string, verbose bool) error {
	argv := []string{"chroot", root}
	argv = append(argv, args...)

	if verbose {
		log.CmdArray(argv)
	}

	cmd := system.NewCommand(argv[0], argv[1:]...)
	_, err := s.Run(cmd)
	return err
}
