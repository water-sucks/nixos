{
  description = "A unified NixOS tooling replacement for nixos-* utilities";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

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
        system,
        ...
      }: let
        zig = inputs.zig-overlay.packages.${system}."0.11.0";

        inherit (inputs.gitignore.lib) gitignoreSource;
      in {
        packages.default = pkgs.stdenvNoCC.mkDerivation {
          pname = "nixos";
          version = "0.1.0";
          src = gitignoreSource ./.;

          nativeBuildInputs = [zig];

          dontConfigure = true;
          dontInstall = true;

          buildPhase = ''
            mkdir -p $out
            mkdir -p .cache/{p,z,tmp}
            zig build install \
              --cache-dir $(pwd)/zig-cache \
              --global-cache-dir $(pwd)/.cache \
              -Dcpu=baseline \
              -Doptimize=ReleaseSafe \
              --prefix $out
          '';

          meta = with pkgs.lib; {
            homepage = "https://github.com/water-sucks/nixos";
            description = "A unified NixOS tooling replacement for nixos-* utilities";
            license = licenses.gpl3Only;
            maintainers = with maintainers; [water-sucks];
          };
        };

        devShells.default = pkgs.mkShell {
          name = "nixos-shell";
          packages = [
            pkgs.alejandra
            pkgs.zls
          ];
          nativeBuildInputs = [
            zig
          ];

          ZIG_DOCS = "${zig}/doc/langref.html";
          ZIG_STD_DOCS = "${zig}/doc/std/index.html";
        };
      };

      flake = {
        nixosModules = {
          nixos-cli = import ./module.nix self;
        };
      };
    };
}
