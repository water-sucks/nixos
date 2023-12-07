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

    # Configuration for `nixos init`
    environment.etc."nixos-cli/init-config.json".source = let
      # Inherit this from the old nixos-generate-config attrs. Easy to deal with, for now.
      desktopConfig = lib.concatStringsSep "\n" config.system.nixos-generate-config.desktopConfiguration;
    in
      jsonFormat.generate "nixos-init-config.json" {
        hostPlatform = pkgs.stdenv.hostPlatform.system;
        xserverEnabled = config.services.xserver.enable;
        inherit desktopConfig;
        extraAttrs = [];
        extraConfig = "";
      };

    # Hijack system builder commands to insert a `nixos-version.json` file at the root.
    system.systemBuilderCommands = let
      nixos-version-json = let
        nixosCfg = config.system.nixos;
      in
        builtins.toJSON {
          nixosVersion = "${nixosCfg.distroName} ${nixosCfg.release} (${nixosCfg.codeName})";
          nixpkgsRevision = "${nixosCfg.revision}";
          configurationRevision = "${config.system.configurationRevision}";
        };
    in ''
      cat > "$out/nixos-version.json" << EOF
      ${nixos-version-json}
      EOF
    '';
  };
}
