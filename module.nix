self: {
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.nixos-cli;
  inherit (lib) types;

  jsonFormat = pkgs.formats.json {};
in {
  options.services.nixos-cli = {
    enable = lib.mkEnableOption "unified NixOS tooling replacement for nixos-* utilities";

    package = lib.mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      description = "Package to use for nixos-cli";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    environment.etc."nixos-cli/generate-config.json".source = let
      # Inherit this from the old nixos-generate-config attrs. Easy to deal with, for now.
      desktopConfig = lib.concatStringsSep "\n" config.system.nixos-generate-config.desktopConfiguration;
    in
      jsonFormat.generate "nixos-generate-config.json" {
        hostPlatform = pkgs.stdenv.hostPlatform.system;
        xserverEnabled = config.services.xserver.enable;
        inherit desktopConfig;
        extraAttrs = [];
        extraConfig = "";
      };
  };
}
