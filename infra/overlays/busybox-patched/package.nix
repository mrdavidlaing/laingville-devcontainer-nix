# Busybox 1.37.0 to fix CVEs included in upstream release
# The nixpkgs nixpkgs-unstable includes busybox 1.36.1 with backported patches,
# but scanners still flag it based on version number.
#
# 1.37.0 includes all CVE fixes upstream:
# - CVE-2022-28391: sockaddr2str/nslookup printable character sanitization
# - CVE-2022-48174 (CRITICAL): shell segfault on malformed input
# - CVE-2023-42363, CVE-2023-42364, CVE-2023-42365, CVE-2023-42366: awk fixes
# - tar TOCTOU symlink race condition
#
# Remove this overlay once nixpkgs updates busybox to 1.37.0
# Track: https://github.com/NixOS/nixpkgs/pull/469979
{
  stdenv,
  lib,
  buildPackages,
  fetchurl,
  fetchFromGitLab,
  enableStatic ? stdenv.hostPlatform.isStatic,
  enableMinimal ? false,
  enableAppletSymlinks ? true,
  useMusl ? stdenv.hostPlatform.libc == "musl",
  musl,
  extraConfig ? "",
}:

assert stdenv.hostPlatform.libc == "musl" -> useMusl;

let
  configParser = ''
    function parseconfig {
        while read LINE; do
            NAME=`echo "$LINE" | cut -d \  -f 1`
            OPTION=`echo "$LINE" | cut -d \  -f 2`

            if ! [[ "$NAME" =~ ^CONFIG_ ]]; then continue; fi

            echo "parseconfig: removing $NAME"
            sed -i /$NAME'\(=\| \)'/d .config

            echo "parseconfig: setting $NAME=$OPTION"
            echo "$NAME=$OPTION" >> .config
        done
    }
  '';

  libcConfig = lib.optionalString useMusl ''
    CONFIG_FEATURE_UTMP n
    CONFIG_FEATURE_WTMP n
  '';

  debianVersion = "1.30.1-6";
  debianSource = fetchFromGitLab {
    domain = "salsa.debian.org";
    owner = "installer-team";
    repo = "busybox";
    rev = "debian/1%${debianVersion}";
    sha256 = "sha256-6r0RXtmqGXtJbvLSD1Ma1xpqR8oXL2bBKaUE/cSENL8=";
  };
  debianDispatcherScript = "${debianSource}/debian/tree/udhcpc/etc/udhcpc/default.script";
  outDispatchPath = "$out/default.script";
in

stdenv.mkDerivation rec {
  pname = "busybox";
  version = "1.37.0";

  src = fetchurl {
    url = "https://busybox.net/downloads/${pname}-${version}.tar.bz2";
    sha256 = "sha256-MxHf8y50ZJn03w1d8E1+s5Y4LX4Qi7klDntRm4NwQ6Q=";
  };

  hardeningDisable = [
    "format"
  ]
  ++ lib.optionals enableStatic [ "fortify" ];

  # All CVE patches are now included upstream in 1.37.0
  patches = [
    # Allow BusyBox to be invoked as "<something>-busybox". This is
    # necessary when it's run from the Nix store as <hash>-busybox during
    # stdenv bootstrap.
    ./busybox-in-store.patch
  ]
  ++ lib.optional (stdenv.hostPlatform != stdenv.buildPlatform) ./clang-cross.patch;

  separateDebugInfo = true;

  postPatch = "patchShebangs .";

  configurePhase = ''
    export KCONFIG_NOTIMESTAMP=1
    make ${if enableMinimal then "allnoconfig" else "defconfig"}

    ${configParser}

    cat << EOF | parseconfig

    CONFIG_PREFIX "$out"
    CONFIG_INSTALL_NO_USR y

    CONFIG_LFS y

    ${lib.optionalString (!enableMinimal) ''
      CONFIG_FEATURE_MODPROBE_BLACKLIST y
      CONFIG_FEATURE_MODUTILS_ALIAS y
      CONFIG_FEATURE_MODUTILS_SYMBOLS y
      CONFIG_MODPROBE_SMALL n
    ''}

    ${lib.optionalString enableStatic ''
      CONFIG_STATIC y
    ''}

    ${lib.optionalString (!enableAppletSymlinks) ''
      CONFIG_INSTALL_APPLET_DONT y
      CONFIG_INSTALL_APPLET_SYMLINKS n
    ''}

    CONFIG_FEATURE_MOUNT_CIFS n
    CONFIG_FEATURE_MOUNT_HELPERS y

    CONFIG_DEFAULT_SETFONT_DIR "/etc/kbd"

    CONFIG_FEATURE_COPYBUF_KB 64

    CONFIG_TC n

    CONFIG_UDHCPC_DEFAULT_SCRIPT "${outDispatchPath}"

    ${extraConfig}
    CONFIG_CROSS_COMPILER_PREFIX "${stdenv.cc.targetPrefix}"
    ${libcConfig}
    EOF

    make oldconfig

    runHook postConfigure
  '';

  postConfigure = lib.optionalString (useMusl && stdenv.hostPlatform.libc != "musl") ''
    makeFlagsArray+=("CC=${stdenv.cc.targetPrefix}cc -isystem ${musl.dev}/include -B${musl}/lib -L${musl}/lib")
  '';

  makeFlags = [ "SKIP_STRIP=y" ];

  postInstall = ''
    sed -e '
    1 a busybox() { '$out'/bin/busybox "$@"; }\
    logger() { '$out'/bin/logger "$@"; }\
    ' ${debianDispatcherScript} > ${outDispatchPath}
    chmod 555 ${outDispatchPath}
    HOST_PATH=$out/bin patchShebangs --host ${outDispatchPath}
  '';

  strictDeps = true;

  depsBuildBuild = [ buildPackages.stdenv.cc ];

  buildInputs = lib.optionals (enableStatic && !useMusl && stdenv.cc.libc ? static) [
    stdenv.cc.libc
    stdenv.cc.libc.static
  ];

  enableParallelBuilding = true;

  doCheck = false;

  passthru.shellPath = "/bin/ash";

  meta = {
    description = "Tiny versions of common UNIX utilities in a single small executable (1.37.0 with CVE fixes)";
    homepage = "https://busybox.net/";
    license = lib.licenses.gpl2Only;
    mainProgram = "busybox";
    maintainers = with lib.maintainers; [
      TethysSvensson
      qyliss
    ];
    platforms = lib.platforms.linux;
    priority = 15;
  };
}
