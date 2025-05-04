NIXOS-CLI-GENERATION-LIST(1)

# NAME

nixos generation list - list available generations on a NixOS machine

# SYNOPSIS

*nixos generation list* [options]

# DESCRIPTION

List all generations in the current NixOS profile, along with relevant metadata
such as generation number, timestamp, and description.

This command provides both programmatic output formats and an interactive
TUI that can be used to view generations with ease.

By default, this command launches the TUI.

- Use the arrow keys or _hjkl_ to navigate through generations.
- Type _/_ to search by generation number or description.
- Press _<Enter>_ to switch to a given generation.
- Press _<Space>_ to mark generations for deletion (except the current one).
- Press _d_ to delete all marked generations.
- Press _<Ctrl+C>_ or _q_ to exit.

This interface is designed to make reviewing and managing system generations
faster and more user-friendly.

# EXAMPLES

Extract just the generation numbers using *jq*:

	*nixos generation list -j | jq '.[].number'*

List generations in table format without the interactive UI:

	*nixos generation list -t*

Extract just the generation numbers using *cut* from table output:

	*nixos generation list -t | cut -d ' ' -f 1*

# OPTIONS

*-h*, *--help*
	Show the help message for this command.

*-j*, *--json*
	Display the generation list in JSON format. Suitable for scripts or machine
	parsing.

*-t*, *--table*
	Display the generation list in a *grep*-pable table format. Also suitable
	for scripts where JSON parsing is not available.

# SEE ALSO

*nixos-cli-generation-diff(1)*

*nixos-cli-generation-delete(1)*

*nixos-cli-generation-rollback(1)*

*nixos-cli-generation-switch(1)*

# AUTHORS

Maintained by the *nixos-cli* team. See the main man page *nixos-cli(1)* for
details.
