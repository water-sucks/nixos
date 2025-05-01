{
  pkgs ? import <nixpkgs> {},
  lib ? pkgs.lib,
}: let
  flake-self =
    (
      import
      (
        let
          lock = builtins.fromJSON (builtins.readFile ./flake.lock);
        in
          fetchTarball {
            url = "https://github.com/edolstra/flake-compat/archive/${lock.nodes.flake-compat.locked.rev}.tar.gz";
            sha256 = lock.nodes.flake-compat.locked.narHash;
          }
      )
      {src = ./.;}
    )
    .outputs;

  revision = (builtins.fetchGit ./.).rev;
in {
  nixos = pkgs.callPackage ./package.nix {
    flake = true;
    inherit revision;
  };

  nixosLegacy = pkgs.callPackage ./package.nix {
    flake = false;
    inherit revision;
  };

  module = lib.modules.importApply ./module.nix flake-self;
}
