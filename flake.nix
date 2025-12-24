# flake.nix
{
  description = "Nix container infrastructure for laingville";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = import ./overlays;
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ overlays ];
          config.allowUnfree = false;
        };

        #############################################
        # Package Sets - composable building blocks
        #############################################
        packageSets = {
          # Foundation (always included)
          base = with pkgs; [
            bashInteractive  # Interactive shell with readline support
            coreutils        # Basic Unix utilities (ls, cp, mv, etc.)
            findutils        # find, xargs, locate
            gnugrep          # grep for pattern matching
            gnused           # sed for stream editing
            gawk             # awk for text processing
            gnutar           # Required by VS Code to extract server
            gzip             # Required to decompress tar.gz files
            cacert           # TLS/SSL certificates for HTTPS
            tzdata           # Timezone data
          ];

          # VS Code Remote compatibility (provides libraries for VS Code's node binary)
          vscodeCompat = with pkgs; [
            glibc             # GNU C library
            stdenv.cc.cc.lib  # libstdc++ (C++ standard library)
          ];

          # Development tools (for devcontainers)
          devTools = with pkgs; [
            gitMinimal       # Version control (smaller closure than full git)
            curl             # HTTP client
            jq               # JSON processor
            ripgrep          # Fast grep alternative (rg)
            fd               # Fast find alternative
            fzf              # Fuzzy finder
            bat              # cat with syntax highlighting
            diffutils        # diff, cmp, sdiff for file comparison
            just             # Command runner (justfile)
            shadow           # User management (useradd, passwd, etc.)
            sudo             # Privilege escalation
            starship         # Cross-shell prompt
            openssh          # SSH client for Git over SSH and remote access
          ];

          # Nix tooling (for containers that need nix develop)
          nixTools = with pkgs; [
            nix              # Nix package manager
            direnv           # Directory-based environment switching
            nix-direnv       # Fast nix integration for direnv
          ];

          # Language: Python
          python = with pkgs; [
            python312        # Python 3.12 interpreter
          ];
          pythonDev = with pkgs; [
            python312Packages.pip         # Package installer
            python312Packages.virtualenv  # Virtual environment creator
            uv               # Fast Python package installer
            ruff             # Fast Python linter
            pyright          # Python type checker / language server
          ];

          # Language: Node
          # Uses nodejs_22_patched with npm 11.6.4 to fix glob CVE-2025-64756
          node = with pkgs; [
            nodejs_22_patched  # Node.js 22 LTS with patched npm
          ];
          # nodeDev: Uses patched nodePackages.* rebuilt with nodejs_22_patched.
          # The overlay rebuilds nodePackages with npm 11.6.4 (glob 13.0.0, fixed),
          # ensuring they're CVE-free while keeping the convenience of nixpkgs packages.
          nodeDev = with pkgs; [
            bun                                    # Fast JavaScript runtime/bundler
            nodePackages.typescript                # TypeScript compiler (patched)
            nodePackages.typescript-language-server  # TypeScript language server (patched)
            nodePackages.prettier                  # Code formatter (patched)
            nodePackages.eslint                    # JavaScript linter (patched)
          ];

          # Language: Go
          go = with pkgs; [
            go               # Go compiler and tools
          ];
          goDev = with pkgs; [
            gopls            # Go language server
            golangci-lint    # Go linter aggregator
          ];

          # Language: Rust
          rust = with pkgs; [
            rustc            # Rust compiler
            cargo            # Rust package manager
          ];
          rustDev = with pkgs; [
            rust-analyzer    # Rust language server
            clippy           # Rust linter
            rustfmt          # Rust code formatter
          ];

          # Language: Bash
          bash = with pkgs; [
            # bashInteractive already included in base package set
          ];
          bashDev = with pkgs; [
            shellcheck       # Shell script static analysis tool
            shellspec        # BDD testing framework for shell scripts
            shfmt            # Shell script formatter
            kcov             # Code coverage tool (used by ShellSpec --kcov)
          ];
        };

        #############################################
        # Builder Functions
        #############################################

        # mkDevContainer: Creates a development container
        # - vscode user (uid 1000) by default
        # - sudo access
        # - direnv hook in bashrc
        # - Nix configured for flakes
        mkDevContainer = {
          packages,
          name ? "devcontainer",
          tag ? "latest",
          user ? "vscode",
          extraConfig ? {}
        }:
          let
            shell = "${pkgs.bashInteractive}/bin/bash";
            uid = "1000";
            gid = "1000";
            home = "/home/${user}";
          in
          pkgs.dockerTools.buildLayeredImage {
            inherit name tag;
            contents = packages;
            # Create real files (not symlinks) using fakeRootCommands
            fakeRootCommands = ''
              # Create directories (note: /bin, /lib, /lib64 are created by packages)
              mkdir -p ./etc/sudoers.d ./etc/nix ./etc/direnv
              mkdir -p .${home}/.config/nix .${home}/.config/direnv
              mkdir -p ./root ./tmp ./usr/bin
              chmod 1777 ./tmp

              # Create /usr/bin/env symlink (required by VS Code server scripts)
              ln -s ${pkgs.coreutils}/bin/env ./usr/bin/env
              # /bin/sh is created by bashInteractive package

              # VS Code Remote compatibility
              # Create os-release to identify as nixos (skips VS Code's glibc check)
              cat > ./etc/os-release <<OSRELEASE
ID=nixos
NAME="NixOS"
OSRELEASE

              # passwd - must be a real file, not symlink
              cat > ./etc/passwd <<EOF
root:x:0:0:root:/root:${shell}
${user}:x:${uid}:${gid}:${user}:${home}:${shell}
EOF

              # group
              cat > ./etc/group <<EOF
root:x:0:
wheel:x:10:${user}
${user}:x:${gid}:
EOF

              # shadow
              cat > ./etc/shadow <<EOF
root:!:1::::::
${user}:!:1::::::
EOF
              chmod 640 ./etc/shadow

              # sudoers
              echo "${user} ALL=(ALL) NOPASSWD:ALL" > ./etc/sudoers.d/${user}
              chmod 440 ./etc/sudoers.d/${user}

              # nix config
              cat > ./etc/nix/nix.conf <<EOF
experimental-features = nix-command flakes
accept-flake-config = true
EOF

              # direnv config
              cat > ./etc/direnv/direnvrc <<EOF
source ${pkgs.nix-direnv}/share/nix-direnv/direnvrc
EOF

              # user bashrc
              cat > .${home}/.bashrc <<'BASHRC'
eval "$(direnv hook bash)"
eval "$(starship init bash)"
BASHRC

              # starship config (minimal, fast prompt)
              mkdir -p .${home}/.config
              cat > .${home}/.config/starship.toml <<'STARSHIP'
# Minimal devcontainer prompt
format = "$directory$git_branch$git_status$nix_shell$character"

[directory]
truncation_length = 3
truncate_to_repo = true

[git_branch]
format = "[$branch]($style) "
style = "bold purple"

[git_status]
format = '([$all_status$ahead_behind]($style) )'
style = "bold red"

[nix_shell]
format = '[$symbol$state]($style) '
symbol = "❄️ "
style = "bold blue"

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
STARSHIP

              # user nix config
              cat > .${home}/.config/nix/nix.conf <<EOF
experimental-features = nix-command flakes
accept-flake-config = true
EOF

              # user direnv config
              cat > .${home}/.config/direnv/direnvrc <<EOF
source ${pkgs.nix-direnv}/share/nix-direnv/direnvrc
EOF

              # Fix ownership
              chown -R ${uid}:${gid} .${home}
            '';
            config = {
              User = user;
              WorkingDir = "/workspace";
              Env = [
                "HOME=${home}"
                "USER=${user}"
                "PATH=${home}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin"
                "NIX_PATH=nixpkgs=channel:nixpkgs-unstable"
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                # VS Code Remote compatibility - provide libraries via LD_LIBRARY_PATH
                # This allows VS Code's node binary to find glibc and libstdc++ without patching
                "LD_LIBRARY_PATH=${pkgs.glibc}/lib:${pkgs.stdenv.cc.cc.lib}/lib"
              ];
              Cmd = [ shell ];
            } // extraConfig;
            maxLayers = 100;
          };

        # mkRuntime: Creates a minimal production container
        # - app user (uid 1000, non-root) by default
        # - No development tools
        # - No Nix (unless explicitly included in packages)
        mkRuntime = {
          packages,
          name ? "runtime",
          tag ? "latest",
          user ? "app",
          workdir ? "/app",
          extraConfig ? {}
        }:
          let
            shell = "${pkgs.bashInteractive}/bin/bash";
            uid = "1000";
            gid = "1000";
          in
          pkgs.dockerTools.buildLayeredImage {
            inherit name tag;
            contents = packages;
            # Create real files (not symlinks) using fakeRootCommands
            fakeRootCommands = ''
              # Create directories (note: /bin is created by packages)
              mkdir -p ./etc
              mkdir -p .${workdir}
              mkdir -p ./root ./tmp ./usr/bin
              chmod 1777 ./tmp

              # Create /usr/bin/env symlink (required by many scripts)
              ln -s ${pkgs.coreutils}/bin/env ./usr/bin/env
              # /bin/sh is created by bashInteractive package

              # passwd - must be a real file, not symlink
              cat > ./etc/passwd <<EOF
root:x:0:0:root:/root:${shell}
${user}:x:${uid}:${gid}:${user}:${workdir}:${shell}
EOF

              # group
              cat > ./etc/group <<EOF
root:x:0:
${user}:x:${gid}:
EOF

              # shadow
              cat > ./etc/shadow <<EOF
root:!:1::::::
${user}:!:1::::::
EOF
              chmod 640 ./etc/shadow

              # Fix ownership
              chown -R ${uid}:${gid} .${workdir}
            '';
            config = {
              User = user;
              WorkingDir = workdir;
              Env = [
                "HOME=${workdir}"
                "USER=${user}"
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                # Provide libraries for pre-compiled binaries that expect FHS paths
                "LD_LIBRARY_PATH=${pkgs.glibc}/lib:${pkgs.stdenv.cc.cc.lib}/lib"
              ];
            } // extraConfig;
            maxLayers = 50;
          };

      in
      {
        # Export package sets for projects to use
        inherit packageSets;

        # Export builder functions
        lib = {
          inherit mkDevContainer mkRuntime;
        };

        # DevShells - for local development without containers
        devShells = {
          default = pkgs.mkShell {
            name = "infra-dev";
            packages = with pkgs; [
              git
              direnv
              nix-direnv
            ];
          };

          python = pkgs.mkShell {
            name = "python-dev";
            packages = packageSets.base ++ packageSets.python ++ packageSets.pythonDev;
            shellHook = ''
              echo "Python devShell activated"
            '';
          };

          node = pkgs.mkShell {
            name = "node-dev";
            packages = packageSets.base ++ packageSets.node ++ packageSets.nodeDev;
            shellHook = ''
              echo "Node devShell activated"
            '';
          };
        };

        # Example container images (for testing/demo)
        # Projects should build their own using mkDevContainer/mkRuntime
        packages = {
          # Laingville devcontainer - for developing this repository
          # Includes Nix tooling and Bash development tools (shellcheck, shellspec)
          laingville-devcontainer = mkDevContainer {
            name = "ghcr.io/mrdavidlaing/laingville-devcontainer-nix/laingville-devcontainer";
            packages = packageSets.base ++ packageSets.vscodeCompat ++ packageSets.nixTools
                    ++ packageSets.devTools ++ packageSets.bashDev;
          };

          # Example devcontainer with Python
          example-python-devcontainer = mkDevContainer {
            name = "ghcr.io/mrdavidlaing/laingville-devcontainer-nix/example-python-devcontainer";
            packages = packageSets.base ++ packageSets.vscodeCompat ++ packageSets.nixTools
                    ++ packageSets.devTools ++ packageSets.python ++ packageSets.pythonDev;
          };

          # Example runtime with Python
          example-python-runtime = mkRuntime {
            name = "ghcr.io/mrdavidlaing/laingville-devcontainer-nix/example-python-runtime";
            packages = packageSets.base ++ packageSets.python;
          };

          # Example devcontainer with Node
          example-node-devcontainer = mkDevContainer {
            name = "ghcr.io/mrdavidlaing/laingville-devcontainer-nix/example-node-devcontainer";
            packages = packageSets.base ++ packageSets.vscodeCompat ++ packageSets.nixTools
                    ++ packageSets.devTools ++ packageSets.node ++ packageSets.nodeDev;
          };

          # Example runtime with Node
          example-node-runtime = mkRuntime {
            name = "ghcr.io/mrdavidlaing/laingville-devcontainer-nix/example-node-runtime";
            packages = packageSets.base ++ packageSets.node;
          };
        };
      }
    );
}
