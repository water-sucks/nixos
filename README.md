<h1 align="center">nixos</h1>
<h6 align="center">A unified NixOS management tool.</h6>

## Introduction

<table class="alert-warn" align=center>
<tr>
    <td>🚨</td>
    <td>
      This project will be undergoing a rewrite to make it more feasible to
      work on certain features, and also to make development time faster.
      If you want to use this rewrite early, point to the
      <a href="https://github.com/water-sucks/nixos/tree/rewrite">
        <code>rewrite</code>
      </a> branch.
      <p>
        The rewrite will also bring some substantial UX improvements, and
        hopefully some new things on the roadmap. Stay tuned!
      </p>
    </td>
</tr>
</table>

This is a unification of all the different pick NixOS tooling into one executable.
NixOS has its various tools spread out between several large scripts that have
become on the verge of unmaintainable. This tool has one goal: to create a modular
NixOS CLI that mirrors or enhances the functionality of all current NixOS tooling in
`nixpkgs`, adds on to it if needed, and eventually come to replace it entirely.

- `nixos-rebuild` → `nixos apply` + `nixos generation`
- `nixos-enter` → `nixos enter`
- `nixos-generate-config` → `nixos init`
- `nixos-version` → `nixos info`
- `nixos-install` → `nixos install`
- `nixos-info` → `nixos manual`
- `nixos-option` → `nixos option`

More to come in the future, see [TODO](#todo) for a list of commands that are
planned to be implemented.

## Usage

Use this repo as a flake input. A NixOS module is also provided, and this is
the recommended way to use this program.

```nix
{
  inputs.nixos-cli.url = "github:water-sucks/nixos";

  outputs = { nixpkgs, nixos-cli, ... }: {
    nixosConfigurations.system-name = nixpkgs.lib.nixosSystem {
      modules = [
        nixos-cli.nixosModules.nixos-cli
        {
          services.nixos-cli = {
            enable = true;
            # Other configuration for nixos-cli
          };
        }
        # other configuration goes here
      ];
    };
  };
}
```

### Cache

There is a Cachix cache available. Add the following to your NixOS configuration
to avoid lengthy rebuilds and fetching extra build-time dependencies:

```nix
{
  nix.settings = {
    substituters = [ "https://watersucks.cachix.org" ];
    trusted-public-keys = [
      "watersucks.cachix.org-1:6gadPC5R8iLWQ3EUtfu3GFrVY7X6I4Fwz/ihW25Jbv8="
    ];
  };
}
```

Or if using the Cachix CLI outside a NixOS environment:

```sh
$ cachix use watersucks
```

There are rare cases in which you want to automatically configure a cache when
using flakes, such as when installing NixOS configurations using this tool.
The following configuration in the `flake.nix` can help with this (beware
though, as this is a fairly undocumented feature!):

```nix
{
  nixConfig = {
    extra-substituters = [ "https://watersucks.cachix.org" ];
    extra-trusted-public-keys = [
      "watersucks.cachix.org-1:6gadPC5R8iLWQ3EUtfu3GFrVY7X6I4Fwz/ihW25Jbv8="
    ];
  };

  inputs = {}; # Whatever you normally have here
  outputs = inputs: {}; # Whatever you normally have here
}
```

## Legacy

This is primarily a flake-oriented package, since flakes are the future, at
least as far as can be seen. However, legacy configurations managed with
`nix-channel` and a `configuration.nix` are maintained here as well, albeit they
are a little harder to use. The `nixos-cli` package that manages legacy
configurations is completely separated from the flake-enabled `nixos-cli`, as
to not mix usage between the two and separate concerns. In order to use the
NixOS module, one must add the following to `configuration.nix` (or wherever
`imports` are specified) in order to use the NixOS module properly:

```nix
{ config, system, pkgs, ...}:

let
  # Make sure to specify the git revision to fetch the flake in pure eval mode.
  nixos-cli = builtins.getFlake "github:water-sucks/nixos/GITREVDEADBEEFDEADBEEF0000";
in {
  imports = [
    (nixos-cli).nixosModules.nixos-cli
  ];

  services.nixos-cli = {
    enable = true;
    package = nixos-cli.packages.${pkgs.system}.nixosLegacy;
    # Other configuration for nixos-cli
  };

  nix.settings.extra-experimental-features = ["flakes"];

  # ... rest of config
}
```

Note that this does involve flakes to be an enabled feature. If this is a
deal-breaker for some reason, then please file an issue; legacy configurations
are actively supported.

## Configuration

This can be configured using the NixOS module (the preferred way), which
generates a file at `/etc/nixos-cli/config.toml`. A path to a configuration
file can also be specified using the `NIXOS_CLI_CONFIG` environment variable.

A sample configuration file with all available options, along with some example
configuration is located in [`config.sample.toml`](./config.sample.toml).

## TODO

### Implemented Commands/Flags

- ➖ `apply`
- ❌ `container`
- ✅ `enter`
- ✅ `info`
- ✅ `init`
- ➖ `install`
- ✅ `generation`
  - ✅ `list`
  - ✅ `switch`
  - ✅ `rollback`
  - ✅ `delete`
  - ✅ `diff`
- ✅ `manual`
- ✅ `option`
- ✅ `repl`

### Roadmap

- ❌ CLI completion
- ❌ Documentation (via man pages)
- ✅ Options search (a la https://search.nixos.org)
- ❌ Remote installation (a la [`nixos-anywhere`](https;//github.com/numtide/nixos-anywhere))
- ❌ Remote application of configurations
- ❌ Container management (Maybe? This is lower priority.)

Check the [issues](https://github.com/water-sucks/nixos/issues) page for more on
this; this is just a high-level overview.

## Talk!

Join the Matrix room at [#nixos-cli:matrix.org](https://matrix.to/#/#nixos-cli:matrix.org)!
It's open for chatting about NixOS in general, and for making it a better
experience for all that involved.

I would like for this to become a standard NixOS tool, which means that I want
to cater to potentially many interests. If you would like for any commands
to be implemented that you think fit this project, talk to me on Matrix or
file a GitHub issue.
