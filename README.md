<h1 align="center">nixos</h1>
<h6 align="center">A unified NixOS management tool.</h6>

## Introduction

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
        # other configuration goes here
      ];
    };
  };
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
generates a file at `/etc/nixos-cli/config.toml`. An absolute path to a
configuration file can also be specified using the `NIXOS_CLI_CONFIG`
environment variable.

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
- ➖ `generation`
  - ✅ `list`
  - ✅ `switch <number>`
  - ✅ `rollback`
  - ➖ `diff` (a la [nvd](https://gitlab.com/khumba/nvd))
- ✅ `manual`
- ❌ `option`
- ✅ `repl`

### Possible Future Commands

I would like for this to become a standard NixOS tool, which means that I want
to cater to potentially many interests. If you would like for any subcommands
to be implemented that you think fit this project, please file an issue.
