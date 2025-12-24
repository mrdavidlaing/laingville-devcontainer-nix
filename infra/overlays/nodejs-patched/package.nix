# Patched nodejs package with npm 11.6.4 to fix glob CVE-2025-64756
# The upstream nodejs_22 bundles npm 10.9.4 with glob 10.4.5 (vulnerable)
# npm 11.6.4 includes glob 13.0.0 (fixed)
#
# This overlay wraps the original nodejs_22 and replaces its npm with 11.6.4.
# Used for container images where we need CVE-free npm but don't need nodePackages.
#
# Important: do NOT leave runtime symlinks back to the original nodejs_22 output.
# If we do, the original nodejs_22 store path (and its bundled vulnerable npm)
# remains in the container closure and gets scanned. We copy the node binary
# (and headers) instead.
#
# Remove once nixpkgs updates nodejs with npm containing fixed glob.
# Track: https://github.com/npm/cli/releases - glob should be >= 10.5.0
{
  lib,
  stdenv,
  fetchurl,
  nodejs_22,
  makeWrapper,
}:

let
  # npm 11.6.4 tarball from npm registry
  # Hash obtained via: nix-prefetch-url https://registry.npmjs.org/npm/-/npm-11.6.4.tgz --type sha256
  npmTarball = fetchurl {
    url = "https://registry.npmjs.org/npm/-/npm-11.6.4.tgz";
    hash = "sha256-nAftyhKFPN2/T+1ONySFqmDAZPm/PkzRV6LbVRiheSs=";
  };

  # Extract npm to a derivation
  npmPackage = stdenv.mkDerivation {
    pname = "npm-standalone";
    version = "11.6.4";
    src = npmTarball;

    # npm tarball extracts to "package/" directory
    sourceRoot = "package";

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/node_modules/npm
      cp -r . $out/lib/node_modules/npm/
      runHook postInstall
    '';

    meta = {
      description = "npm package manager (standalone, version 11.6.4)";
      homepage = "https://www.npmjs.com/";
      license = lib.licenses.artistic2;
    };
  };

in
stdenv.mkDerivation {
  pname = "nodejs-patched";
  # Use original nodejs version for srcOnly compatibility (it derives source name from version)
  inherit (nodejs_22) version;

  # Source for srcOnly (used by npmHooks.npmConfigHook for node-gyp headers)
  # buildNpmPackage's hooks use `srcOnly nodejs` to get nodejs source
  inherit (nodejs_22) src;

  # Don't unpack since we're just wrapping binaries
  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib/node_modules $out/share/man $out/include

    # Copy node binary from original nodejs (avoid runtime reference to nodejs_22)
    # shellcheck disable=SC2154
    install -m 0755 ${nodejs_22}/bin/node $out/bin/node

    # Copy include directory if present (needed for native module compilation)
    if [ -d "${nodejs_22}/include" ] && [ "$(ls -A ${nodejs_22}/include 2>/dev/null)" ]; then
      cp -r ${nodejs_22}/include/* $out/include/
    fi

    # Don't copy share/man from original nodejs as it contains symlinks to
    # the bundled npm which we're replacing. npm 11.6.4 doesn't include man pages.

    # Note: we intentionally do NOT include corepack in containers.
    # It adds a lot of extra JS dependencies (and scanners flag them) while
    # being unnecessary for our devcontainers/runtimes.

    # Use our patched npm instead of the bundled one
    cp -r ${npmPackage}/lib/node_modules/npm $out/lib/node_modules/npm

    # Create npm wrapper that uses our node
    makeWrapper $out/bin/node $out/bin/npm \
      --add-flags "$out/lib/node_modules/npm/bin/npm-cli.js"

    # Create npx wrapper
    makeWrapper $out/bin/node $out/bin/npx \
      --add-flags "$out/lib/node_modules/npm/bin/npx-cli.js"

    runHook postInstall
  '';

  # Inherit meta from original nodejs so buildNpmPackage can access platforms
  meta = nodejs_22.meta // {
    description = "Node.js with patched npm 11.6.4 (CVE-2025-64756 fix)";
  };

  # Pass through all attributes that buildNpmPackage and other tools expect
  # This includes python (for node-gyp builds), pkgs (for nodePackages), etc.
  passthru = nodejs_22.passthru or {};

  # Expose python directly (buildNpmPackage accesses nodejs.python)
  python = nodejs_22.python;
}
