NIXOS-CLI-ENV(5)

# NAME

nixos-cli-env - environment variables used by *nixos-cli*

# DESCRIPTION

The *nixos-cli* tool is influenced by a number of environment variables. These
allow the user to configure the CLI's behavior at runtime, such as:

- Default inputs
- Formatting preferences

Among other things.

# ENVIRONMENT VARIABLES

*NO_COLOR*
	Disable colored output in *nixos-cli*.

	Does not apply to terminal user interfaces (TUIs), which manage their own
	display logic.

*NIXOS_CLI_CONFIG*
	Specify a custom path for the *nixos-cli* settings file. 

	Default: */etc/nixos-cli/config.toml*

*NIXOS_CONFIG*
	Defines the configuration that *nixos-cli* will operate on.
	Its meaning depends on whether the CLI is built with flake support.

	This environment variable takes precedence over the *config_location*
	setting if it is set.

	- *Flake-enabled CLIs:*
	  This must be a valid flake ref (e.g., */home/user/config* or
	  *github:myorg/nixos-config*).

	  Flake refs without a local path may have slightly different behavior,
	  such as not supporting implicit Git operations. Check relevant man pages
	  for more information.

	  Paths _MUST_ be absolute. Use *realpath(1)* if you must.

	- *Legacy CLIs:*
	  This can be a path to a configuration file directly (*configuration.nix*),
	  or a directory containing a *default.nix*.

	  Legacy configurations can also be sourced from the *$NIX_PATH* environment
	  variable, if the _nixos-config=<PATH>_ attribute is specified there.

*NIXOS_CLI_DISABLE_STEPS*
	Disable showing visual steps with the logger. These "steps" get converted to
	information logs internally if this is set.

	Mostly useful for internal implementation, rather than for end-users.

*NIXOS_CLI_DEBUG_MODE*
	Show log messages for when developing TUIs. Only useful for during
	development.

# SEE ALSO

*nixos-cli-config(5)*

# AUTHORS

Maintained by the *nixos-cli* team. See the main man page *nixos-cli(1)* for
details.
