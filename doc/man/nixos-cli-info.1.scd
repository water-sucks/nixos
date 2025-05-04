NIXOS-CLI-INFO(1)

# NAME

nixos info - show information about the currently running NixOS generation

# SYNOPSIS

*nixos info* [options]

# DESCRIPTION

The *nixos info* command displays metadata about the currently active NixOS
generation.

This includes generation number, activation time, system profile, and
configuration details.

It can be useful for diagnostics, system reporting, or to confirming that a
deployment has succeeded.

Currently, this command only shows the generation number when using the
_system_ profile, due to the fact that there is no reliable way to tell
what profile is being used.

# OPTIONS

*-h*, *--help*
	Show the help message for this command.

*-j*, *--json*
	Output the information as a structured JSON object.

*-m*, *--markdown*
	Format the output as Markdown, useful for pasting into issue reports or
	documentation.

# SEE ALSO

*nixos-cli-generation-list(1)*

# AUTHORS

Maintained by the *nixos-cli* team. See the main man page *nixos-cli(1)* for
details.
