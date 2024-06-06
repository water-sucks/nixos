{
  description = "A unified NixOS tooling replacement for nixos-* utilities";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    # Make sure this flake input is in sync with the Zig-fetched package
    # by updating the corresponding dependency inside build.zig.zon.
    # Otherwise, the symbols exported by Nix may # not be guaranteed to
    # be the same as the ones in the upstream Nix bindings package.
    zignix.url = "github:water-sucks/zignix";

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

      perSystem = {
        pkgs,
        lib,
        system,
        ...
      }: let
        nixPackage = inputs.zignix.inputs.nix.packages.${system}.nix;
      in {
        packages = rec {
          default = nixos;
          nixos = pkgs.callPackage (import ./package.nix) {
            revision = self.rev or "dirty";
            nix = nixPackage;
          };
          nixosLegacy = nixos.override {flake = false;};
        };

        devShells.default = pkgs.mkShell {
          name = "nixos-shell";
          nativeBuildInputs = [
            pkgs.zig
            pkgs.pkg-config
          ];
          buildInputs = [
            nixPackage.dev
          ];

          ZIG_DOCS = "${pkgs.zig}/doc/langref.html";
        };
      };

      flake = {
        nixosModules = {
          nixos-cli = import ./module.nix self;
        };
      };
    };
}
