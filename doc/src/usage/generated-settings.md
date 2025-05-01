## General

- **`aliases`**

  Defines alternative aliases for long commands to improve user ergonomics.
Example:
```toml[aliases]
genlist = ["generation", "list"]
switch = ["generation", "switch"]
rollback = ["generation", "rollback"]
```


  **Default**: `[]`

- **`color`**

  Turns on ANSI color sequences for decorated output in supported terminals.

  **Default**: `true`

- **`config_location`**

  Path to a Nix file or directory to look for user configuration in by default.

  **Default**: `/etc/nixos`

- **`no_confirm`**

  Disables prompts that ask for user confirmation, useful for automation.

  **Default**: `false`

- **`root_command`**

  Specifies which command to use for privilege escalation (e.g., sudo or doas).

  **Default**: `sudo`

- **`use_nvd`**

  Use the better-looking `nvd` diffing tool when comparing configurations instead of `nix store diff-closures`.

  **Default**: `false`


## `apply`

Settings for `apply` command

- **`apply.ignore_dirty_tree`**

  Allows 'apply' to use Git commit messages even when the working directory is dirty.

  **Default**: `false`

- **`apply.imply_impure_with_tag`**

  Automatically appends '--impure' to the 'apply' command when using '--tag' in flake-based workflows.

  **Default**: `false`

- **`apply.specialisation`**

  Specifies which systemd specialisation to use when activating a configuration with 'apply'.

  **Default**: ""

- **`apply.use_git_commit_msg`**

  When enabled, the last Git commit message will be used as the value for '--tag' automatically.

  **Default**: `false`

- **`apply.use_nom`**

  Enables nix-output-monitor to show more user-friendly build progress output for the 'apply' command.

  **Default**: `false`


## `enter`

Settings for `enter` command

- **`enter.mount_resolv_conf`**

  Ensures internet access by mounting the host's /etc/resolv.conf into the chroot environment.

  **Default**: `true`


## `init`

Settings for `init` command

- **`init.desktop_config`**

  Specifies the desktop environment configuration to inject during initialization.

  **Default**: ""

- **`init.extra_attrs`**

  

  **Default**: `[]`

- **`init.extra_config`**

  

  **Default**: ""

- **`init.xserver_enabled`**

  Controls whether X11-related services and packages are configured by default during init.

  **Default**: `false`


## `option`

Settings for `option` command

- **`option.debounce_time`**

  Controls how often search results are recomputed when typing in the options UI, in milliseconds.

  **Default**: `25`

- **`option.min_score`**

  Sets the cutoff score for showing results in fuzzy-matched option lookups.

  **Default**: `1`

- **`option.prettify`**

  If enabled, renders option documentation in a prettier Markdown format where applicable.

  **Default**: `true`


