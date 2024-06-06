let
  fetchZigDeps = {
    stdenv,
    zig,
  }: {
    name,
    src,
    packageRoot ? "./",
    depsHash,
  } @ args:
    stdenv.mkDerivation {
      name = "${name}-deps";

      nativeBuildInputs = [zig];

      inherit src;

      configurePhase =
        args.modConfigurePhase
        or ''
          runHook preConfigure
          cd "${packageRoot}"
          runHook postConfigure
        '';

      buildPhase = ''
        # export CACHE_DIR=$(mktemp -d)
        runHook preBuild
        zig build --fetch --global-cache-dir "./zig-cache" --cache-dir "./zig-cache"
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        cp -r --reflink=auto zig-cache/p $out
        runHook postInstall
      '';

      dontFixup = true;
      dontPatchShebangs = true;

      outputHashMode = "recursive";
      outputHash = depsHash;
    };
in
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
  }:
    stdenv.mkDerivation rec {
      pname = "nixos";
      version = "0.7.0-dev";
      src = nix-gitignore.gitignoreSource [] ./.;

      postPatch = let
        deps = fetchZigDeps {inherit stdenv zig;} {
          name = pname;
          src = ./.;
          depsHash = "sha256-AtdKKvLYR865JRKKgNwiejo5kKEO88vg1N6GXdBBIsk=";
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
