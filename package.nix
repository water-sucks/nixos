{
  lib,
  buildGoModule,
  nix-gitignore,
  installShellFiles,
  revision ? "unknown",
  flake ? true,
  ...
}:
buildGoModule rec {
  pname = "nixos";
  version = "0.11.1-dev";
  src = nix-gitignore.gitignoreSource [] ./.;

  vendorHash = "sha256-Jw8dasyyQd4E/96jo6XB0gdiPDX3O96Nm8mn21fVx9g=";

  nativeBuildInputs = [installShellFiles];

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

    installShellCompletion --cmd nixos \
      --bash <($out/bin/nixos completion bash) \
      --fish <($out/bin/nixos completion fish) \
      --zsh <($out/bin/nixos completion zsh)
  '';

  meta = with lib; {
    homepage = "https://github.com/water-sucks/nixos";
    description = "A unified NixOS tooling replacement for nixos-* utilities";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [water-sucks];
  };
}
