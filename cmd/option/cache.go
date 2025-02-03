package option

import (
	"bytes"
	"fmt"
	"path/filepath"

	"github.com/water-sucks/nixos/internal/configuration"
	"github.com/water-sucks/nixos/internal/constants"
	"github.com/water-sucks/nixos/internal/system"
)

const (
	flakeOptionsCacheExpr = `let
  flake = builtins.getFlake "%s";
  system = flake.nixosConfigurations."%s";
  inherit (system) pkgs;
  inherit (pkgs) lib;

  optionsList' = lib.optionAttrSetToDocList system.options;
  optionsList = builtins.filter (v: v.visible && !v.internal) optionsList';

  jsonFormat = pkgs.formats.json {};
in
  jsonFormat.generate "options-cache.json" optionsList
`
	legacyOptionsCacheExpr = `let
  system = import <nixpkgs/nixos> {};
  inherit (system) pkgs;
  inherit (pkgs) lib;

  optionsList' = lib.optionAttrSetToDocList system.options;
  optionsList = builtins.filter (v: v.visible && !v.internal) optionsList';

  jsonFormat = pkgs.formats.json {};
in
  jsonFormat.generate "options-cache.json" optionsList
`
)

var prebuiltOptionCachePath = filepath.Join(constants.CurrentSystem, "etc", "nixos-cli", "options-cache.json")

func buildOptionCache(s system.CommandRunner, cfg configuration.Configuration) (string, error) {
	argv := []string{"nix-build", "--no-out-link", "--expr"}

	switch v := cfg.(type) {
	case *configuration.FlakeRef:
		argv = append(argv, fmt.Sprintf(flakeOptionsCacheExpr, v.URI, v.System))
	case *configuration.LegacyConfiguration:
		argv = append(argv, legacyOptionsCacheExpr)
		for _, v := range v.Includes {
			argv = append(argv, "-I", v)
		}
	}

	cmd := system.NewCommand(argv[0], argv[1:]...)

	var stdout bytes.Buffer
	cmd.Stdout = &stdout

	_, err := s.Run(cmd)
	if err != nil {
		return "", err
	}

	return stdout.String(), nil
}
