# Comparisons to Existing NixOS Tools

## [`nh`](https://github.com/nix-community/nh)

`nh` is a more popular application in this realm, perhaps because it looked
prettier due to the earlier `nix-output-monitor` and `nvd` integration, and is
significantly older than `nixos-cli`.

However, I prefer to keep the focus on NixOS here, while `nh` tries to be a
unified `rebuild` + `switch` manager for multiple OSes. That's the biggest
difference.

`nixos-cli` also has more features than `nh` for NixOS-based machines, so that's
a plus.

In the future, I may want to write similar CLIs to `nixos-cli` as replacements
for the current `darwin-rebuild` and `home-manager` scripts, but this is purely
imaginative for the time being. My personal belief is that these are
fundamentally separate projects with vaguely similar, but disparate concerns,
and in my opinion, should be kept that way.

## [`nixos-rebuild-ng`](https://github.com/NixOS/nixpkgs/tree/master/pkgs/by-name/ni/nixos-rebuild-ng) + [`switch-to-configuration-ng`](https://github.com/NixOS/nixpkgs/tree/master/pkgs/by-name/sw/switch-to-configuration-ng)

The big differences:

- They mimic the existing `nixos-rebuild.sh` project 1:1 when it comes to
  features
- They're two separate projects still written in two separate languages
- They are developed in the `nixpkgs` tree, so it's harder to track progress

`nixos-cli` intends to go much further than these. The interface is much more
approachable, and the development is done out-of-tree, which makes it easier to
separate concerns.

Also, the plan in the future is to have a `nixos activate` command that is a
self-contained drop-in replacement for `switch-to-configuration` functionality,
rather than being two separate projects. The progress for this is tracked in
[this GitHub issue](https://github.com/nix-community/nixos-cli/issues/55).

Also, the `nixos-rebuild-ng` project is written in Python, which would require a
Python runtime as a builtin dependency for base NixOS systems with it, while
`nixos-cli` only requires the Go compiler.
