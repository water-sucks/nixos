## [``services.nixos-cli.enable``](https://github.com/water-sucks/nixos/blob/d6e11f7629ce7c6c428131f944096ba60dfc76da/module.nix#L16)

unified NixOS tooling replacement for nixos-* utilities

**Type:** `boolean`

**Default:** `false`

**Example:** `true`

## [``services.nixos-cli.package``](https://github.com/water-sucks/nixos/blob/d6e11f7629ce7c6c428131f944096ba60dfc76da/module.nix#L18)

Package to use for nixos-cli

**Type:** `types.package`

**Default:** `self.packages.${pkgs.system}.nixos`

## [``services.nixos-cli.config``](https://github.com/water-sucks/nixos/blob/d6e11f7629ce7c6c428131f944096ba60dfc76da/module.nix#L24)

Configuration for nixos-cli, in TOML format

**Type:** `tomlFormat.type`

**Default:** `{}`

## [``services.nixos-cli.generationTag``](https://github.com/water-sucks/nixos/blob/d6e11f7629ce7c6c428131f944096ba60dfc76da/module.nix#L42)

A description for this generation

**Type:** `types.nullOr types.str`

**Default:** `lib.maybeEnv "NIXOS_GENERATION_TAG" null`

**Example:** `"Sign Git GPG commits by default"`

## [``services.nixos-cli.prebuildOptionCache``](https://github.com/water-sucks/nixos/blob/d6e11f7629ce7c6c428131f944096ba60dfc76da/module.nix#L49)

Prebuild JSON cache for `nixos option` command

**Type:** `types.bool`

**Default:** `config.documentation.nixos.enable`

---
*Generated with [nix-options-doc](https://github.com/Thunderbottom/nix-options-doc)*
