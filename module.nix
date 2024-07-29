self: {
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.nixos-cli;
  nixosCfg = config.system.nixos;

  inherit (lib) types;

  tomlFormat = pkgs.formats.toml {};
in {
  options.services.nixos-cli = {
    enable = lib.mkEnableOption "unified NixOS tooling replacement for nixos-* utilities";

    package = lib.mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      description = "Package to use for nixos-cli";
    };

    config = lib.mkOption {
      type = tomlFormat.type;
      default = {};
      description = "Configuration for nixos-cli, in TOML format";
      apply = prev: let
        # Inherit this from the old nixos-generate-config attrs. Easy to deal with, for now.
        desktopConfig = lib.concatStringsSep "\n" config.system.nixos-generate-config.desktopConfiguration;
      in
        lib.recursiveUpdate {
          init = {
            xserver_enabled = config.services.xserver.enable;
            desktop_config = desktopConfig;
            extra_config = "";
          };
        }
        prev;
    };

    generationTag = lib.mkOption {
      type = types.nullOr types.str;
      default = lib.maybeEnv "NIXOS_GENERATION_TAG" null;
      description = "A description for this generation";
      example = "Sign Git GPG commits by default";
    };

    prebuildOptionCache = lib.mkOption {
      type = types.bool;
      default = config.documentation.nixos.enable;
      description = "Prebuild JSON cache for `nixos option` command";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = let
      optionsJSON = config.system.build.manual.optionsJSON;
    in
      [cfg.package] ++ lib.optionals cfg.prebuildOptionCache [optionsJSON];

    environment.etc."nixos-cli/config.toml".source =
      tomlFormat.generate "nixos-cli-config.toml" cfg.config;

    # Hijack system builder commands to insert a `nixos-version.json` file at the root.
    system.systemBuilderCommands = let
      nixos-version-json = builtins.toJSON {
        nixosVersion = "${nixosCfg.distroName} ${nixosCfg.release} (${nixosCfg.codeName})";
        nixpkgsRevision = "${nixosCfg.revision}";
        configurationRevision = "${builtins.toString config.system.configurationRevision}";
        description = cfg.generationTag;
      };
    in ''
      cat > "$out/nixos-version.json" << EOF
      ${nixos-version-json}
      EOF
    '';

    security.sudo.extraConfig = ''
      # Preserve NIXOS_CONFIG and NIXOS_CLI_CONFIG in sudo invocations of
      # `nixos apply`. This is required in order to keep ownership across
      # automatic re-exec as root.
      Defaults env_keep += "NIXOS_CONFIG"
      Defaults env_keep += "NIXOS_CLI_CONFIG"
    '';
  };
}
