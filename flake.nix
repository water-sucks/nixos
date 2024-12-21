{
  description = "A unified NixOS tooling replacement for nixos-* utilities";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-parts,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [];

      systems = nixpkgs.lib.systems.flakeExposed;

      perSystem = {pkgs, ...}: let
        inherit (pkgs) callPackage go golangci-lint mkShell;
      in {
        packages = rec {
          default = nixos;

          nixos = callPackage (import ./package.nix) {
            revision = self.rev or "dirty";
          };
          # nixosLegacy = nixos.override {flake = false;};
        };

        devShells.default = mkShell {
          name = "nixos-shell";
          nativeBuildInputs = [
            go
            golangci-lint
          ];
        };
      };

      flake = {
        nixosModules = {
          nixos-cli = import ./module.nix self;
        };
      };
    };
}
