NIXOS-CLI-GENERATION-DIFF(1)

# NAME

nixos generation diff - display differences between two generations

# SYNOPSIS

*nixos generation diff* [BEFORE] [AFTER] [flags]

# DESCRIPTION

Compare two NixOS system generations and show which paths differ between them.
This can help users understand what changed between deployments.

Both generation numbers must exist and belong to the same profile.

The output highlights differing store paths or system configuration files
between the two specified generations.

The diff command that is ran can be one of two options:

	- *nix store diff-closures* (default)
	- *nvd*, which has prettier output (if the setting _use_nvd_ is set and
	if it is installed)

# OPTIONS

*-h*, *--help*
	Show the help message for this command.

*-v*, *--verbose*
	Enable verbose logging, including more detailed output of differing paths.

# ARGUMENTS

*BEFORE*
	Generation number to compare from.

*AFTER*
	Generation number to compare against.

# SEE ALSO

*nixos-generation(1)*

*nixos-cli-generation-list(1)*

*nix3-store-diff-closures(1)*

# AUTHORS

Maintained by the *nixos-cli* team. See the main man page *nixos-cli(1)* for
details.
