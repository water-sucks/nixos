NIXOS-CLI(1)

# NAME

nixos-cli - a tool for managing NixOS installations

# SYNOPSIS

*nixos* [command] [options]

# COMMANDS

*apply*
	Build and/or activate a NixOS configuration. This includes evaluating the
	NixOS module system, building the system derivation, and switching to the
	new generation.

*enter*
	Enter a chroot environment using a provided NixOS installation root. Useful
	for debugging, performing repairs, or running commands in the target system
	context.

*features*
	Show metadata and features supported by this build of the CLI. This is
	mostly useful for diagnosing issues.

*generation*
	List, remove, or inspect generations of the system. Works similarly to
	_nix-env --list-generations_ but scoped to the NixOS CLI context.

*info*
	Display information about the currently running generation on the local
	system.

*init*
	Initialize a new NixOS configuration in the current directory. This sets up
	a default configuration, likely including hardware discovery and system
	flake scaffolding.

*install*
	Perform a full system install of NixOS, including setting up the target
	drive, copying a configuration, and activating the system.

*manual*
	Open the official NixOS manual in the default browser. This is equivalent to
	navigating to <https://nixos.org/manual> but integrated into the CLI.

*option*
	Query the NixOS option system. This allows searching for options, reading
	their documentation, defaults, types, and current values.

*repl*
	Start a Nix REPL preloaded with the system configuration and modules. Useful
	for experimentation and debugging.

# OPTIONS

*--color-always*
	Always produce colored output when possible. By default, output may be
	auto-detected for TTYs.

*--config <KEY>=<VALUE>*
	Override configuration settings directly on the command line. Multiple values
	can be passed.

	Example: *--config use_nvd=true --config option.prettify=false*

*-h, --help*
	Show the help message for this command.

*--version*
	Display the version of the `nixos-cli` tool.

# AUTHORS

Maintained by Varun Narravula <varun@snare.dev>. Up-to-date sources can be
found at https://github.com/water-sucks/nixos, and bugs reports or patches can
be submitted to GitHub's issue tracker.

# SEE ALSO

*nixos-cli-apply(1)*
*nixos-cli-enter(1)*
*nixos-cli-features(1)*
*nixos-cli-generation(1)*
*nixos-cli-info(1)*
*nixos-cli-init(1)*
*nixos-cli-install(1)*
*nixos-cli-manual(1)*
*nixos-cli-option(1)*
*nixos-cli-repl(1)*

*nixos-cli-settings(5)*
*nixos-cli-env(5)*
