# Introduction - `nixos-cli`

`nixos-cli` is a robust, cohesive, drop-in replacement for NixOS tooling such as
`nixos-rebuild`, among many other tools.

## Why?

NixOS tooling today is fragmented across large, aging shell and other assorted
scripts/projects that are difficult to maintain or extend. Prolific examples
include:

- [`nixos-rebuild.sh`](https://github.com/NixOS/nixpkgs/blob/master/pkgs/os-specific/linux/nixos-rebuild/nixos-rebuild.sh)
  (a mess of convoluted Bash)
- [`switch-to-configuration-ng`](https://github.com/NixOS/nixpkgs/tree/master/pkgs/by-name/sw/switch-to-configuration-ng),
  (a Rust project), as well as the old implementation in Perl

These tools contain deep functionality, but much of it is hidden, hard to
modify, or locked behind poor ergonomics.

`nixos-cli` aims to modernize this experience by:

- Replacing and improving existing tooling
- Providing a consistent interface across all commands
- Making functionality more accessible and extensible
- Offering a clean, discoverable CLI experience for both users and developers

In summary, this tool has one goal: to create a modular NixOS CLI that mirrors
or enhances the functionality of all current NixOS tooling in `nixpkgs`, adds on
to it if needed, and eventually **come to replace it entirely**.

Yes, this is already being done somewhat by `switch-to-configuration-ng` and
`nixos-rebuild-ng`. However, `nixos-cli` strives to achieve further goals,
including (but not limited to the following)

- Enhanced usability (and looking nice! Who doesn't love eye candy?)
- Deeper integration with NixOS internals
- Creating a self-contained NixOS manager binary that includes routine scripts
  such as `switch-to-configuration` activation functionality
- Plugins for further NixOS tooling to be developed out-of-tree

Check the [comparisons](./comparisons.md) page for an overview of how this tool
differs from existing ecosystem tools.

## Key Features

- Drop-in replacements for common NixOS tools (with better names!)
- An integrated NixOS option search UI
- An improved generation manager, with an additional UI (more fine-tuned than
  `nix-collect-garbage -d`)

Check out the [overview](./overview.md) page for more information about key
features.

More features are planned; see the [roadmap](roadmap.md) for more information.

## Status

This tool is under **active development**, but is **not yet stable**.  
Until a 1.0 release, the CLI interface and configuration may change without
notice.

Watch the [Releases](https://github.com/nix-community/nixos-cli/releases) page
for:

- Breaking changes
- Feature updates
- Bug fixes

Core contributors:

- [`@water-sucks`](https://github.com/water-sucks)

Contributions, testing, and bug reports/general feedback are highly encouraged,
since there are few people working on this project actively.

## Talk!

Join the Matrix room at
[#nixos-cli:matrix.org](https://matrix.to/#/#nixos-cli:matrix.org)! It's open
for chatting about NixOS in general, and for making it a better experience for
all that involved.
