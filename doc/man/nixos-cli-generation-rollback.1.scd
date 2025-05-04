NIXOS-CLI-GENERATION-ROLLBACK(1)

# NAME

nixos generation rollback - rollback to the previous NixOS generation

# SYNOPSIS

*nixos generation rollback* [options]

# DESCRIPTION

Rollback to the previous NixOS generation number, if it exists. Similar to
*nixos generation switch*, except the generation number is not required, and
as such, is a little more ergonomic to use in most situations where a rollback
is required.

*NOTE*: This only relies on the number to determine the last generation that was
activated; as such, it does not actually rollback to the last generation
number that was switched to, since there is no record of this.

Useful for rolling back to a known good state or testing previous
configurations.

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

# SEE ALSO

*nixos-cli-generation-list*(1)

*nixos-cli-generation-switch*(1)

*nixos-cli-apply(1)*

# AUTHORS

Maintained by the *nixos-cli* team. See the main man page *nixos-cli(1)* for
details.
