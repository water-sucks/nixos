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
  let
    inherit (nixpkgs) lib;
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [];

      systems = lib.systems.flakeExposed;

      perSystem = {pkgs, self', ...}: let
        inherit (pkgs) callPackage go golangci-lint mkShell;
      in {
        packages = {
          default = self'.packages.nixos;

          nixos = callPackage ./package.nix {
            revision = self.rev or self.dirtyRev or "unknown";
          };
          nixosLegacy = self'.packages.nixos.override {flake = false;};
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
          nixos-cli = lib.modules.importApply ./module.nix self;
        };
      };
    };
}
