NIXOS-INIT(1)

# NAME

nixos init - initialize a NixOS configuration template and/or hardware options

# SYNOPSIS

*nixos init* [options]

# DESCRIPTION

The *nixos init* command scaffolds a basic NixOS configuration in the specified
root directory and/or updates hardware configurations depending on what is
detected on the system.

It is primarily used before a system installation to create an initial
_configuration.nix_ and hardware settings, or after installation to
automatically update a given hardware configuration.

Two files are generated for all systems:

_/path/to/configuration.nix_
	A main NixOS system configuration module. Only generated when it does not
	exist, unless *--force* is passed.

_/path/to/hardware_configuration.nix_
	A module that sets NixOS configuration options based on the current
	hardware and filesystems that are detected. Examples of these types of
	configurations include
		- Kernel modules required for the hardware
		- Detected filesystems
		- Detected swap partitions
		- _initrd_ options for booting the system

	This gets regenerated, and shouldn't be touched much, since changes are
	overwritten each time this command is ran.

Depending on if the CLI is flake-enabled, a _flake.nix_ file may also be
generated for new configurations.

# EXAMPLES

Create a new NixOS configuration in /mnt for installation:

	*nixos init --root /mnt*

Print a NixOS hardware configuration module to stdout and redirect to a file:

	*nixos init --show-hardware-config > path/to/hwconfig.nix*

# OPTIONS

*-d*, *--dir* _path_
	Directory inside the root where configuration files will be written.

	This gets concatenated to the *--root* option, so paths will take the form
	of _/mnt/etc/nixos_ if *--root* is _/mnt_

	Default: */etc/nixos*

*-f*, *--force*
	Forcefully generate all configuration files, overwriting any existing ones
	for _configuration.nix_ (and _flake.nix_, if applicable).

*-h*, *--help*
	Show the help message for this command.

*-n*, *--no-fs*
	Skip generation of _fileSystems_ and _swapDevices_ configuration options.

	Useful if disk options are to be managed separately/manually, such as
	through external modules.

*-r*, *--root* <PATH>
	Treat *PATH* as the root directory of the system.

	Default: */*

*-s*, *--show-hardware-config*
	Print the generated hardware configuration to stdout and exit.

	No files will be written when this option is used.

# SEE ALSO

*nixos-cli-install(1)*

# AUTHORS

Maintained by the *nixos-cli* team. See the main man page *nixos-cli(1)* for
details.
