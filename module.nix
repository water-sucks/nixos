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

    config = lib.mkOption {
      type = jsonFormat.type;
      default = {};
      description = "Configuration for nixos-cli, in JSON format";
      apply = prev: let
        # Inherit this from the old nixos-generate-config attrs. Easy to deal with, for now.
        desktopConfig = lib.concatStringsSep "\n" config.system.nixos-generate-config.desktopConfiguration;
      in
        lib.recursiveUpdate {
          init = {
            xserver_enabled = config.services.xserver.enable;
            desktop_config = desktopConfig;
            extra_attrs = [];
            extra_config = "";
          };
        }
        prev;
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    environment.etc."nixos-cli/config.json".source =
      jsonFormat.generate "nixos-cli-config.json" cfg.config;

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

    # Preserve NIXOS_CONFIG in sudo invocations of `nixos build`
    security.sudo.extraConfig = ''
      Defaults env_keep += "NIXOS_CONFIG"
    '';
  };
}
