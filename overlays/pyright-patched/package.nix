# Patched pyright package with esbuild 0.27.1 to fix Go stdlib CVEs
# esbuild 0.27.0+ is compiled with Go 1.25.4 which fixes:
# - CVE-2025-61729 (HIGH): HostnameError.Error() resource exhaustion
# - CVE-2025-58187 (HIGH): x509 name constraint checking DoS
# - CVE-2025-58186 (HIGH): HTTP cookie parsing memory exhaustion
# - CVE-2025-58183 (HIGH): archive/tar sparse map allocation
# - Plus ~20 additional medium severity Go stdlib CVEs
# Also uses nodejs_22_patched to fix glob CVE-2025-64756
# Remove this overlay once nixpkgs updates pyright with fixed esbuild
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  runCommand,
  jq,
  nodejs_22_patched,
}:

let
  version = "1.1.407";

  src = fetchFromGitHub {
    owner = "Microsoft";
    repo = "pyright";
    tag = version;
    hash = "sha256-TQrmA65CzXar++79DLRWINaMsjoqNFdvNlwDzAcqOjM=";
  };

  patchedPackageJSON = runCommand "package.json" { } ''
    ${jq}/bin/jq '
      .devDependencies |= with_entries(select(.key == "glob" or .key == "jsonc-parser"))
      | .scripts =  {  }
      ' ${src}/package.json > $out
  '';

# Patch pyright-internal's package.json to use esbuild 0.27.1 (Go 1.25.4).
# NOTE: `esbuild-loader` pins `esbuild` to ^0.25.0 (0.25.x only), which pulls in
# a vulnerable Go stdlib via `@esbuild/*` gobinaries and gets flagged by container
# scanners even though we don't run the build pipeline in Nix (`dontNpmBuild=true`).
# We use npm `overrides` to force esbuild 0.27.1 everywhere, allowing us to keep
# `esbuild-loader` while ensuring the runtime closure uses the patched esbuild.
  # Why pin `esbuild` to an exact version (not ^0.27.1)?
  # - Reproducibility: this derivation is driven by `package-lock.json` + `npmDepsHash`.
  #   Allowing semver ranges makes it easier to accidentally regenerate locks/hashes with
  #   a newer esbuild, causing non-obvious hash mismatches and CI-only failures.
  # - Security determinism: esbuild ships platform-specific Go gobinaries (@esbuild/*).
  #   Pinning keeps the embedded Go stdlib version (and the CVE surface) predictable.
  #
  # If you bump esbuild:
  # - Regenerate `pyright-internal-package-lock.json`
  # - Update `npmDepsHash` in this file
  patchedInternalPackageJSON = runCommand "pyright-internal-package.json" { } ''
    ${jq}/bin/jq '
      .devDependencies["esbuild"] = "0.27.1"
      | .overrides = {
          "esbuild": "0.27.1",
          "@esbuild/aix-ppc64": "0.27.1",
          "@esbuild/android-arm": "0.27.1",
          "@esbuild/android-arm64": "0.27.1",
          "@esbuild/android-x64": "0.27.1",
          "@esbuild/darwin-arm64": "0.27.1",
          "@esbuild/darwin-x64": "0.27.1",
          "@esbuild/freebsd-arm64": "0.27.1",
          "@esbuild/freebsd-x64": "0.27.1",
          "@esbuild/linux-arm": "0.27.1",
          "@esbuild/linux-arm64": "0.27.1",
          "@esbuild/linux-ia32": "0.27.1",
          "@esbuild/linux-loong64": "0.27.1",
          "@esbuild/linux-mips64el": "0.27.1",
          "@esbuild/linux-ppc64": "0.27.1",
          "@esbuild/linux-riscv64": "0.27.1",
          "@esbuild/linux-s390x": "0.27.1",
          "@esbuild/linux-x64": "0.27.1",
          "@esbuild/netbsd-arm64": "0.27.1",
          "@esbuild/netbsd-x64": "0.27.1",
          "@esbuild/openbsd-arm64": "0.27.1",
          "@esbuild/openbsd-x64": "0.27.1",
          "@esbuild/openharmony-arm64": "0.27.1",
          "@esbuild/sunos-x64": "0.27.1",
          "@esbuild/win32-arm64": "0.27.1",
          "@esbuild/win32-ia32": "0.27.1",
          "@esbuild/win32-x64": "0.27.1"
        }
      ' ${src}/packages/pyright-internal/package.json > $out
  '';

  pyright-root = buildNpmPackage {
    pname = "pyright-root";
    inherit version src;
    nodejs = nodejs_22_patched;  # Use patched nodejs with npm 11.6.4 (glob CVE fix)
    sourceRoot = "${src.name}"; # required for update.sh script
    npmDepsHash = "sha256-4DVWWoLnNXoJ6eWeQuOzAVjcvo75Y2nM/HwQvAEN4ME=";
    dontNpmBuild = true;
    postPatch = ''
      cp ${patchedPackageJSON} ./package.json
      cp ${./package-lock.json} ./package-lock.json
    '';
    installPhase = ''
      runHook preInstall
      cp -r . "$out"
      runHook postInstall
    '';
  };

  pyright-internal = buildNpmPackage {
    pname = "pyright-internal";
    inherit version src;
    nodejs = nodejs_22_patched;  # Use patched nodejs with npm 11.6.4 (glob CVE fix)
    sourceRoot = "${src.name}/packages/pyright-internal";
    # Updated hash after adding overrides to force esbuild 0.27.1 (CVE fixes)
    # Hash calculated from package-lock.json with npm overrides for esbuild 0.27.1
    npmDepsHash = "sha256-/SQyEJZ9pCkHx+7ZJkmLsNUfcyxjDNXjvQI6ZI9qrGE=";
    dontNpmBuild = true;
    postPatch = ''
      cp ${patchedInternalPackageJSON} ./package.json
      cp ${./pyright-internal-package-lock.json} ./package-lock.json
    '';
    installPhase = ''
      runHook preInstall
      cp -r . "$out"
      runHook postInstall
    '';
  };
in
buildNpmPackage rec {
  pname = "pyright";
  inherit version src;
  nodejs = nodejs_22_patched;  # Use patched nodejs with npm 11.6.4 (glob CVE fix)

  sourceRoot = "${src.name}/packages/pyright";
  npmDepsHash = "sha256-NyZAvboojw9gTj52WrdNIL2Oyy2wtpVnb5JyxKLJqWM=";

  postPatch = ''
    chmod +w ../../
    ln -s ${pyright-root}/node_modules ../../node_modules
    chmod +w ../pyright-internal
    ln -s ${pyright-internal}/node_modules ../pyright-internal/node_modules
  '';

  dontNpmBuild = true;

  meta = {
    changelog = "https://github.com/Microsoft/pyright/releases/tag/${src.tag}";
    description = "Type checker for the Python language (patched with esbuild 0.27.1 for CVE fixes)";
    homepage = "https://github.com/Microsoft/pyright";
    license = lib.licenses.mit;
    mainProgram = "pyright";
    maintainers = with lib.maintainers; [ kalekseev ];
  };
}
