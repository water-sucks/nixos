<h1 align="center">nixos</h1>
<h6 align="center">A unified NixOS management tool.</h6>

## Introduction

This is a unification of all the different pick NixOS tooling into one executable.
Why? Because why not, to be honest. Written in Zig, because I like Zig.

`nixos` replaces these tools with respective subcommmands, listed below:

- `nixos-rebuild` → `nixos build`
- `nixos-enter` → `nixos enter`

More to come in the future, see [TODO](#todo) for a list
of commands and flags that are planned to be implemented.

## Differences to Standard NixOS Tooling

- It's 1 tool, not 10 different ones with roughly similar options
- No mishmash of monstrous Bash and Perl scripts
- It's written in Zig!

## TODO

### Implemented Commands/Flags

- [ ] `build`
  - [x] `--activate`
  - [x] `--boot`
  - [ ] `--build-host <host>`
  - [x] `--dry`
  - [x] `--flake <flake-uri#name>`
  - [x] `--install-bootloader`
  - [x] `--no-flake`
  - [ ] `--no-build-nix`
  - [x] `--output <location>`
  - [x] `--profile-name <name>`
  - [x] `--specialisation <name>`
  - [x] `--switch`
  - [ ] `--target-host <host>`
  - [x] `--upgrade`
  - [x] `--upgrade-all`
  - [ ] `--use-remote-sudo`
  - [x] `--vm`
  - [x] `--vm-with-bootloader`
  - [x] `--verbose`
  - [x] Nix build options
  - [ ] Nix flake options
  - [ ] Nix copy closure options
- [ ] `container`
  - [ ] `list`
  - [ ] `create <name>`
    - [ ] `--auto-start`
    - [ ] `--bridge <iface>`
    - [ ] `--config <string>`
    - [ ] `--config-file <path>`
    - [ ] `--ensure-unique-name`
    - [ ] `--flake <flake-uri#name>`
    - [ ] `--host-address <address>`
    - [ ] `--local-address <address>`
    - [ ] `--nixos-path <path>`
    - [ ] `--port <port>`
    - [ ] `--system-path <path>`
  - [ ] `destroy <name>`
  - [ ] `start <name>`
  - [ ] `stop <name>`
  - [ ] `status <name>`
  - [ ] `update <name>`
    - [ ] `--nixos-path <path>`
    - [ ] `--config <string>`
    - [ ] `--config-file <path>`
    - [ ] `--flake <flake-uri#name>`
  - [ ] `login <name>`
    - [ ] `--root`
  - [ ] `run <name> <args...>`
  - [ ] `show-ip <name>`
  - [ ] `show-host-key <name>`
- [x] `enter`
  - [x] `--command <cmd>`
  - [x] `--root <directory>`
  - [x] `--silent`
  - [x] `--system <directory>`
  - [x] `--`
- [ ] `edit-config`
- [ ] `generate-config`
  - [ ] `--flake`
  - [ ] `--force`
  - [ ] `--root <directory>`
  - [ ] `--dir <directory>`
  - [ ] `--show-hardware-config`
- [ ] `info`
  - [ ] `--nixpkgs-revision`
  - [ ] `--configuration-revision`
  - [ ] `--json`
  - [ ] `--markdown`
- [ ] `manual`
- [ ] `install`
  - [ ] `--closure <path>`
  - [ ] `--channel <derivation>`
  - [ ] `--flake <flake-uri#name>`
  - [ ] `--root`
  - [ ] `--verbose`
  - [ ] Nix build options
  - [ ] Nix flake options
- [ ] `option`
  - [ ] `--list`
  - [ ] `--json`
- [ ] `rollback`
  - [ ] `--choose`
  - [ ] `--generation <number>`
