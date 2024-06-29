{
  stdenv,
  lib,
  zig,
  nix-gitignore,
  pkg-config,
  autoPatchelfHook,
  nix,
  revision ? "dirty",
  flake ? true,
  fetchZigDeps,
}:
stdenv.mkDerivation rec {
  pname = "nixos";
  version = "0.8.0-dev";
  src = nix-gitignore.gitignoreSource [] ./.;

  postPatch = let
    deps = fetchZigDeps {
      inherit stdenv zig;
      name = pname;
      src = ./.;
      depsHash = "sha256-I7yZiQ78wRy9pF0UJTOVxEH9RJ2hNPgkSXfTZfUOk7Y=";
    };
  in ''
    mkdir -p .cache
    ln -s ${deps} .cache/p
  '';

  nativeBuildInputs = [zig pkg-config autoPatchelfHook];

  buildInputs = [nix.dev];

  dontConfigure = true;
  dontInstall = true;

  _NIXOS_GIT_REV = revision;

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

  meta = with lib; {
    homepage = "https://github.com/water-sucks/nixos";
    description = "A unified NixOS tooling replacement for nixos-* utilities";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [water-sucks];
  };
}
