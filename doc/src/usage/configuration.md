# Configuration Settings

This document describes all available settings and their default values.

## General

- **`color`** (default: `true`): Enable colored output
- **`config_location`** (default: `/etc/nixos`): Where to look for configuration by default
- **`no_confirm`** (default: `false`): Disable interactive confirmation input
- **`root_command`** (default: `sudo`): Command to use to promote process to root
- **`use_nvd`** (default: `false`): Use 'nvd' instead of 'nix store diff-closures'

## `apply`

Settings for 'apply' command

- **`apply.imply_impure_with_tag`** (default: `false`): Add --impure automatically when using --tag with flakes
- **`apply.specialisation`** (default: ``): Name of specialisation to use by default when activating
- **`apply.use_nom`** (default: `false`): Use 'nix-output-monitor' as an alternative 'nix build' frontend
- **`apply.use_git_commit_msg`** (default: `false`): Use last git commit message for --tag by default
- **`apply.ignore_dirty_tree`** (default: `false`): Ignore dirty working tree when using Git commit message for --tag

## `enter`

Settings for 'enter' command

- **`enter.mount_resolv_conf`** (default: `true`): Bind-mount host 'resolv.conf' inside chroot for internet accesss

## `init`

Settings for 'init' command

- **`init.xserver_enabled`** (default: `false`): Generate options to enable X11 display server
- **`init.desktop_config`** (default: ``): Config options for desktop environment

## `option`

Settings for 'option' command

- **`option.min_score`** (default: `1`): Minimum distance score to consider an option a match
- **`option.prettify`** (default: `true`): Attempt to render option descriptions using Markdown
- **`option.debounce_time`** (default: `25`): Debounce time for searching options using the UI, in milliseconds
