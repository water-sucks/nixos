NIXOS-CLI-MANUAL(1)

# NAME

nixos manual - open the NixOS manual in a browser

# SYNOPSIS

*nixos manual*

# DESCRIPTION

Opens the NixOS manual in your default web browser.

This command is a convenience wrapper that launches the appropriate URL for the
NixOS manual associated with your configuration. It is especially helpful for
quickly referencing system configuration options and NixOS concepts.

The manual opened is based on the version of Nixpkgs currently in use by your
system, unless the manual is not present on the local system in question.

# ENVIRONMENT

The behavior of this command can be influenced by the *$BROWSERS* environment
variable, which determines which browser is used to open the manual.

If *$BROWSERS* is not set, the command attempts to fall back on a sensible
system default (*xdg-open*).

Examples of `BROWSER` usage:

	*BROWSER=firefox nixos manual*

	*BROWSER=brave nixos manual*

	*BROWSER=w3m nixos manual*

# OPTIONS

*-h*, *--help*
	Show the help message for this command.

## SEE ALSO

*xdg-open(1)*

# AUTHORS

Maintained by the *nixos-cli* team. See the main man page *nixos-cli(1)* for
details.
