# infra/overlays/custom-builds.nix
# Custom compilation flags and build options
final: prev: {
  # Example: GnuCOBOL with VBISAM instead of Berkeley DB
  # gnucobol = prev.gnucobol.override {
  #   useBerkeleyDB = false;
  # };
}
