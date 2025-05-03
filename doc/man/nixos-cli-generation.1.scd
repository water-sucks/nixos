NIXOS-GENERATION(1)

# NAME

nixos generation - manage NixOS generations on this machine

# SYNOPSIS

*nixos generation* [command] [options]

# DESCRIPTION

The *nixos generation* command provides subcommands for managing NixOS system
generations.

This is the other component to *nixos apply* that replaces the existing
*nixos-rebuild(1)* command's functionality.

Generations are snapshots of system configurations that can be listed,
activated, compared, or deleted in the same way as any other Nix closure.

As such, this command allows you to explore previous system states, switch
between them, or inspect changes across generations.

# EXAMPLES

Examples are provided in each subcommand's respective man page.

# COMMANDS

*delete*
	Delete one or more generations from the specified profile based on a range
	of constraints.

*diff*
	Show differences between two generations, such as package changes or option
	modifications.

*list*
	List all generations available in the system profile.

*rollback*
	Activate the generation prior to the current one.

*switch*
	Activate a specified existing generation.

# OPTIONS

*-p*, *--profile* <NAME>
	Specify the system profile *NAME* to operate on; this should contain all
	the generations that will be worked with.

	Default: *system*

*-h*, *--help*  
	Show the help message for this command.

# SEE ALSO

*nixos-cli-generation-delete*(1)

*nixos-cli-generation-diff*(1)

*nixos-cli-generation-list*(1)

*nixos-cli-generation-rollback*(1)

*nixos-cli-generation-switch*(1)

*nixos-cli-apply(1)*

# AUTHORS

Maintained by the *nixos-cli* team. See the main man page *nixos-cli(1)* for
details.
