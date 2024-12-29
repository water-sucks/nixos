{
  lib,
  buildGoModule,
  nix-gitignore,
  revision ? "unknown",
  flake ? true,
  ...
}:
buildGoModule rec {
  pname = "nixos";
  version = "0.11.1-dev";
  src = nix-gitignore.gitignoreSource [] ./.;

  vendorHash = "sha256-wP2XfIiERzZALWyb38ouy7aVgggz6k9x3dgxB2fvZVg=";

  buildPhase = ''
    runHook preBuild
    make \
      VERSION=${version} \
      COMMIT_HASH=${revision} \
      FLAKE=${lib.boolToString flake}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 ./nixos -t $out/bin
    runHook postInstall
  '';

  meta = with lib; {
    homepage = "https://github.com/water-sucks/nixos";
    description = "A unified NixOS tooling replacement for nixos-* utilities";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [water-sucks];
  };
}
