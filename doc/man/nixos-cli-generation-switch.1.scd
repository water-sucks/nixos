NIXOS-CLI-GENERATION-SWITCH(1)

# NAME

nixos generation switch - activate an arbitrary existing NixOS generation

# SYNOPSIS

*nixos generation switch* [GEN] [options]

# DESCRIPTION

Activate a specific, already-existing NixOS generation by its generation number.

Useful for rolling back to a known good state or testing previous
configurations.

# EXAMPLES

Switch to generation 42 with confirmation prompt:

	*nixos generation switch 42*

Dry-run switch to generation 35:

	*nixos generation switch 35 -d*

Switch to generation 18 and automatically confirm:

	*nixos generation switch 18 -y*

Switch to a given specialisation within generation 25:

	*nixos generation switch 25 -s "minimal"*

# OPTIONS

*-d*, *--dry*
	Show what would be activated, but do not perform any actual activation.

	Equivalent to running *switch-to-configuration* manually with the
	*dry-activate* command.

*-h*, *--help*
	Show the help message for this command.

*-s*, *--specialisation* <NAME>
	Activate a specific specialisation *NAME* within the selected generation.

	If the default specialisation is specified in the *nixos-cli* configuration
	for this generation number, and this option is not specified, it will switch
	to that specialisation automatically, rather than using the base one.

*-v*, *--verbose*
	Show verbose logging during activation.

*-y*, *--yes*
	Automatically confirm the generation switch, without prompting.

# ARGUMENTS

*[GEN]*
	The number of the generation to activate.

	This must be an existing generation in the selected NixOS profile.

# SEE ALSO

*nixos-cli-generation-list*(1)

*nixos-cli-generation-rollback*(1)

*nixos-cli-apply(1)*

# AUTHORS

Maintained by the *nixos-cli* team. See the main man page *nixos-cli(1)* for
details.
