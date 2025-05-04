NIXOS-CLI-ENTER(1)

# NAME

nixos-enter - enter a NixOS chroot environment

# SYNOPSIS

*nixos enter* [FLAGS] [-- ARGS...]

# DESCRIPTION

Enter a chroot environment rooted at the specified NixOS installation directory.
This is primarily used for post-installation repair, debugging, or activating a
configuration in an isolated environment.

By default, the command enters _/mnt_ unless another root is specified with
*--root*.

You can execute commands within the chrooted shell using *--command* or by
passing positional arguments after a double dash (`--`).

# EXAMPLES

Enter a chroot in _/path_ and get a login root shell:

	*nixos enter --root /path*

Enter a chroot rooted at _/mnt_ by default, and run a single command (no shell):

	*nixos enter -- ls /etc/nixos*

Enter a different system root with a custom system derivation closure path:

	*nixos enter --system /nix/store/NIX_STORE_HASH/nixos-system...*

Run a command in a chrooted Bash shell and exit:

	*nixos enter --command "nixos-rebuild switch"*

# OPTIONS

*-c*, *--command* <STRING>
	Execute the provided *STRING* in a Bash login shell after entering the
	chroot environment.

	Takes precedence over positional arguments for the command to execute.

*-r*, *--root* <PATH>
	Specify the root *PATH* of the NixOS system to enter.

	Default: */mnt*

*--system* <PATH>
	Manually specify the NixOS system configuration closure *PATH* to activate
	inside the chroot.

*-s*, *--silent*
	Suppress output from the activation scripts and other spurious logging.

*-v*, *--verbose*
	Show verbose logging and diagnostic output during entry and activation.

*-h*, *--help*
	Show the help message for this command.

# ARGUMENTS

*[ARGS...]*
	If provided, arguments are interpreted as the command to execute in the
	environment. Must be preceded by a double dash (`--`) to separate invoked
	command flags from *nixos enter* flags.

	If *--command* is specified, these argumetns will be ignored.

# SEE ALSO

*nixos-apply*(1)

*nixos-install*(1)

*chroot*(1)

# AUTHORS

Maintained by the *nixos-cli* team. See the main man page *nixos-cli(1)* for
details.
