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

## Configuration

This can be configured using the NixOS module (the preferred way), which
generates a file at `/etc/nixos-cli/config.toml`.

The default configuration with all available options and examples is located
in [`config.sample.toml`](./config.sample.toml).

Some of the configuration is a little awkward to specify right now, such
as aliases, but I plan to fix that in the future once I can find a TOML
parsing library that supports dynamic key-value pairs.

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
