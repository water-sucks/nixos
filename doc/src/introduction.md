# Introduction - `nixos-cli`

`nixos-cli` is a robust, cohesive, drop-in replacement for NixOS tooling such as
`nixos-rebuild`, among many other tools.

## Why?

NixOS has its various tools spread out between several large scripts that have
become on the verge of unmaintainable, or that have too much functionality in
them that is not exposed properly. Some examples:

- [`nixos-rebuild.sh`](https://github.com/NixOS/nixpkgs/blob/master/pkgs/os-specific/linux/nixos-rebuild/nixos-rebuild.sh)
- [`switch-to-configuration.pl`](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/system/activation/switch-to-configuration.pl)

This tool has one goal: to create a modular NixOS CLI that mirrors or enhances
the functionality of all current NixOS tooling in `nixpkgs`, adds on to it if
needed, and eventually **come to replace it entirely**.

Yes, this is already being done somewhat by `switch-to-configuration-ng` and
`nixos-rebuild-ng`. However, `nixos-cli` strives to achieve further goals,
including (but not limited to the following)

- Enhanced usability (and looking nice! Who doesn't love eye candy?)
- Deeper integration with NixOS internals
- Creating a self-contained NixOS manager binary that includes routine scripts
  such as `switch-to-configuration` activation functionality
- Plugins for further NixOS tooling to be developed out-of-tree

## Key Features

- Re-implementations of the following commands:
  - `nixos-rebuild` → `nixos apply` + `nixos generation`
  - `nixos-enter` → `nixos enter`
  - `nixos-generate-config` → `nixos init`
  - `nixos-version` → `nixos info`
  - `nixos-install` → `nixos install`
  - `nixos-info` → `nixos manual`
- An integrated NixOS option search UI
- An improved generation manager, with an additional UI (more fine-tuned than
  `nix-collect-garbage -d`)

More features are planned, see the [roadmap](roadmap.md) for more information.

## Status

`nixos-cli` is in active development, but is considered unstable until a 1.0
release. Unstable means that settings and/or command-line flags, as well as any
other exposed resources, are bound to change or break. Watch the
[Releases](https://github.com/water-sucks/nixos/releases) page for more
information about breaking changes as results come in, as well as for new
releases with updated functionality and bug fixes.

Core contributors:

- [`@water-sucks`](https://github.com/water-sucks)

Contributions, testing, and bug reports/general feedback are highly encouraged,
since there are few people working on this project actively.

## Talk!

Join the Matrix room at
[#nixos-cli:matrix.org](https://matrix.to/#/#nixos-cli:matrix.org)! It's open
for chatting about NixOS in general, and for making it a better experience for
all that involved.
