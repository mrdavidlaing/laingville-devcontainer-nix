# infra/overlays/license-fixes.nix
# Recompile packages to avoid copyleft dependencies
final: prev: {
  # Example: ffmpeg without GPL codecs
  # ffmpeg = prev.ffmpeg.override {
  #   withGPL = false;
  # };
}
