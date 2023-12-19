{
  description = "A unified NixOS tooling replacement for nixos-* utilities";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    # Use unstable Nix C bindings
    nix.url = "github:tweag/nix/nix-c-bindings";

    zig-overlay.url = "github:mitchellh/zig-overlay";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    gitignore = {
      url = "github:hercules-ci/gitignore.nix";
      inputs.nixpkgs.follows = "nixpkgs";
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
        zigPackage = inputs.zig-overlay.packages.${system}."0.11.0";
        nixPackage = inputs.nix.packages.${system}.nix;

        inherit (inputs.gitignore.lib) gitignoreSource;

        package = {
          zig,
          pkg-config,
          nix,
          flake ? true,
        }:
          pkgs.stdenv.mkDerivation {
            pname = "nixos";
            version = "0.1.0";
            src = gitignoreSource ./.;

            nativeBuildInputs = [zig pkg-config];

            buildInputs = [nix];

            dontConfigure = true;
            dontInstall = true;

            _NIXOS_GIT_REV = self.rev or "dirty";

            buildPhase = ''
              mkdir -p $out
              zig build install \
                --cache-dir $(pwd)/zig-cache \
                --global-cache-dir $(pwd)/.cache \
                -Dcpu=baseline \
                -Dflake=${lib.boolToString flake} \
                --prefix $out
            '';

            meta = with pkgs.lib; {
              homepage = "https://github.com/water-sucks/nixos";
              description = "A unified NixOS tooling replacement for nixos-* utilities";
              license = licenses.gpl3Only;
              maintainers = with maintainers; [water-sucks];
            };
          };
      in {
        packages = rec {
          default = nixos;
          nixos = pkgs.callPackage package {
            zig = zigPackage;
            nix = nixPackage;
          };
          nixosLegacy = nixos.override {flake = false;};
        };

        devShells.default = pkgs.mkShell {
          name = "nixos-shell";
          packages = [
            pkgs.alejandra
            pkgs.zls
          ];
          nativeBuildInputs = [
            zigPackage
            pkgs.pkg-config
          ];
          buildInputs = [
            nixPackage.dev
          ];

          ZIG_DOCS = "${zigPackage}/doc/langref.html";
          ZIG_STD_DOCS = "${zigPackage}/doc/std/index.html";
        };
      };

      flake = {
        nixosModules = {
          nixos-cli = import ./module.nix self;
        };
      };
    };
}
