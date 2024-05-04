{
  description = "A unified NixOS tooling replacement for nixos-* utilities";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    # Make sure this flake input is in sync with the Zig-fetched package
    # by updating the corresponding dependency inside build.zig.zon and
    # running zon2nix after. Otherwise, the symbols exported by Nix may
    # not be guaranteed to be the same as the ones in the upstream Nix
    # bindings package.
    zignix.url = "github:water-sucks/zignix";

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
        zigPackage = inputs.zig-overlay.packages.${system}."0.12.0";
        nixPackage = inputs.zignix.inputs.nix.packages.${system}.nix;

        inherit (inputs.gitignore.lib) gitignoreSource;

        package = {
          callPackage,
          zig,
          pkg-config,
          autoPatchelfHook,
          nix,
          flake ? true,
        }:
          pkgs.stdenv.mkDerivation {
            pname = "nixos";
            version = "0.7.0";
            src = gitignoreSource ./.;

            postPatch = ''
              mkdir -p .cache
              ln -s ${callPackage ./deps.nix {}} .cache/p
            '';

            nativeBuildInputs = [zig pkg-config autoPatchelfHook];

            buildInputs = [nix.dev];

            dontConfigure = true;
            dontInstall = true;

            _NIXOS_GIT_REV = self.rev or "dirty";

            buildPhase = ''
              mkdir -p $out
              zig build install \
                --cache-dir $(pwd)/zig-cache \
                --global-cache-dir $(pwd)/.cache \
                -Dcpu=baseline \
                -Doptimize=ReleaseSafe \
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
            pkgs.zon2nix
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
