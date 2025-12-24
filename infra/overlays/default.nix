# infra/overlays/default.nix
final: prev:
let
  cvePatches = import ./cve-patches.nix final prev;
  licenseFixes = import ./license-fixes.nix final prev;
  customBuilds = import ./custom-builds.nix final prev;
in
cvePatches // licenseFixes // customBuilds
