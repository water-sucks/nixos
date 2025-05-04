NIXOS-REPL(1)

# NAME

nixos repl - start a Nix REPL with the current system's configuration loaded

# SYNOPSIS

nixos repl [FLAKE-REF] [options]

# DESCRIPTION

Launches an interactive Nix expression evaluator (REPL) preloaded with the
NixOS system configuration.

This command is useful for inspecting the configuration programmatically,
querying attributes, or testing expressions in the context of the active system.

If a flake-enabled CLI is in use, a flake ref may be supplied to specify the
configuration to load; otherwise, *$NIXOS_CONFIG* will be used and _must_
contain a valid flake ref.

If not, the environment variable *$NIXOS_CONFIG* will be
used, or the configuration can be passed through setting the *$NIX_PATH*'s
_nixos-config_ attribute properly through *-I* or elsewhere.

# OPTIONS

*-h*, *--help*
	Show this help menu.

*-I*, *--include*
	Specify an additional location to search for Nix expressions. This behaves
	like passing *-I* to *nix repl* directly.

	It can be used to add custom search paths, such as
	*-I nixpkgs=/path/to/nixpkgs*.

## ARGUMENTS

*FLAKE-REF*  
	Optional flake reference to load attributes from. If the CLI is not
	flake-enabled, this argument is ignored.

	Default: *$NIXOS_CONFIG*

## SEE ALSO

*nix repl(1)*

*nixos-cli-env(5)*

# AUTHORS

Maintained by the *nixos-cli* team. See the main man page *nixos-cli(1)* for
details.
