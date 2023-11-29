<h1 align="center">nixos</h1>
<h6 align="center">A unified NixOS management tool.</h6>

## Introduction

This is a unification of all the different pick NixOS tooling into one executable.
Why? Because why not, to be honest. Written in Zig, because I like Zig.

`nixos` replaces these tools with respective subcommmands, listed below:

- `nixos-rebuild` → `nixos build` + `nixos generation`
- `nixos-enter` → `nixos enter`
- `nixos-generate-config` → `nixos generate-config`

More to come in the future, see [TODO](#todo) for a list
of commands and flags that are planned to be implemented.

## Usage

Use this repo as a flake input. A NixOS module is also provided, and this is
the recommended way to use this program.

```nix
{
  inputs.nixos-cli.url = "github:water-sucks/nixos";

  outputs = { nixpkgs, nixos-cli, ... }: {
    nixosConfigurations.system-name = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-cli.nixosModules.nixos-cli
        # other configuration goes here
      ];
    };
  };
}
```

## Differences to Standard NixOS Tooling

- It's 1 tool, not 10 different ones with roughly similar options
- No mishmash of monstrous Bash and Perl scripts
- It's written in Zig!

## TODO

### Implemented Commands/Flags

- [-] `build`
- [ ] `container`
  - [ ] `list`
  - [ ] `create <name>`
  - [ ] `destroy <name>`
  - [ ] `start <name>`
  - [ ] `stop <name>`
  - [ ] `status <name>`
  - [ ] `update <name>`
  - [ ] `login <name>`
  - [ ] `run <name> <args...>`
  - [ ] `show-ip <name>`
  - [ ] `show-host-key <name>`
- [x] `enter`
- [ ] `edit-config`
- [-] `generate-config`
- [ ] `info`
- [ ] `manual`
- [ ] `install`
- [ ] `option`
- [x] `generation`
  - [x] `list`
  - [x] `switch <number>`
  - [x] `rollback`
  - [?] `diff`

### Possible Future Commands

I would like for this to become a standard NixOS tool, which means that I want
to cater to potentially many interests. If you would like for any subcommands
to be implemented that you think fit this project, please file an issue.
