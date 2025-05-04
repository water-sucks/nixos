NIXOS-CLI-FEATURES(1)

# NAME

nixos features - show metadata about the application and configured options

# SYNOPSIS

*nixos features* [options]

# DESCRIPTION

The *nixos features* command displays metadata about the current build of the
*nixos-cli* application. This includes version information, enabled features,
environment details such as the detected Nix version, and relevant build-time
configuration.

This command is particularly useful for:

- Understanding capabilities of the current *nixos-cli* binary
- Diagnostics for reporting issues
- Debugging issues with the current installation

# OPTIONS

*-j*, *--json*
	Output all metadata in machine-readable JSON format.

*-h*, *--help*
	Show the help message for this command

# AUTHORS

Maintained by the *nixos-cli* team. See the main man page *nixos-cli(1)* for
details.
