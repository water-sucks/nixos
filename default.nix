{pkgs ? import <nixpkgs> {}}: let
  flakeSelf = import ./flake-compat.nix;
in {
  inherit (flakeSelf.packages.${pkgs.system}) nixos nixosLegacy;

  # Do not use lib.importApply here for better error tracking, since
  # it causes an infinite recursion for a currently unknown reason.
  module = import ./module.nix flakeSelf;
}
