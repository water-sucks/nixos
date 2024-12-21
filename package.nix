{
  lib,
  buildGoModule,
  nix-gitignore,
  # revision ? "unknown",
  # flake ? true,
  ...
}:
buildGoModule {
  pname = "nixos";
  version = "0.12.0-dev";
  src = nix-gitignore.gitignoreSource [] ./.;

  vendorHash = "sha256-wP2XfIiERzZALWyb38ouy7aVgggz6k9x3dgxB2fvZVg=";

  meta = with lib; {
    homepage = "https://github.com/water-sucks/nixos";
    description = "A unified NixOS tooling replacement for nixos-* utilities";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [water-sucks];
  };
}
