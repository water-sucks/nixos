# FAQ

## Do you intend on making this an official NixOS application?

Yes! I will be writing an RFC to see if people are interested in this.

That's my ultimate goal, anyway.

## What about [`nh`](https://github.com/nix-community/nh)? Isn't that better since it supports more OSes?

`nh` is a more popular application in this realm, perhaps because it looked
prettier due to the earlier `nix-output-monitor` and `nvd` integration, and is
significantly older than `nixos-cli`.

However, I prefer to keep the focus on NixOS here, while `nh` tries to be a
unified `rebuild` + `switch` manager for multiple OSes. That's the difference.

`nixos-cli` also has more features than `nh` for NixOS-based machines, so that's
a plus.

## What about `home-manager` and `nix-darwin`? Will you support those systems?

They are fundamentally separate projects with roughly similar surfaces, so no. I
am a heavy user of both projects, though, so I may write my own `darwin` and
`hm` CLIs that roughly mirror this.

Think about this:

- `home-manager` has to work in the user context, while NixOS works in the
  system one.
- `nix-darwin` doesn't interact with boot scripts, while NixOS does.

Among a slew of other differences. The `rebuild` + `switch` workflow may be the
same, but the options are different, and I'm lazy. So no.

## Can the option search work with other sources?

It's theoretically possible, as long as the modules can be evaluated with
`lib.evalModules`. As such, `home-manager`, `nix-darwin`, and even `flake-parts`
are possible to do!

However, this tends to significantly increase evaluation time, and will depend
on the system to eval. I plan to break out the option search UI into a separate
project that can be more generalized, and add it back to this one as a plugin of
sorts.

## More questions?

File an issue! Perhaps it's important enough to add to this FAQ as well.
