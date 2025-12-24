# Laingville Nix Container Infrastructure

Project-centric container architecture using pure Nix. Infrastructure provides **package sets** (building blocks) and **builder functions**. Projects compose these to create **project-specific** devcontainer and runtime images with **maximum Docker layer sharing**.

## Quick Start

### Using in a New Project

1. Create a `flake.nix` in your project:

```nix
{
  inputs = {
    infra.url = "github:mrdavidlaing/laingville-devcontainer-nix";
    nixpkgs.follows = "infra/nixpkgs";  # Critical for layer sharing!
  };

  outputs = { self, infra, nixpkgs }:
    let
      system = "x86_64-linux";
      sets = infra.packageSets.${system};
      lib = infra.lib.${system};
    in
    {
      packages.${system} = {
        devcontainer = lib.mkDevContainer {
          name = "ghcr.io/my-org/my-project/devcontainer";
          packages = sets.base ++ sets.nixTools ++ sets.devTools
                  ++ sets.python ++ sets.pythonDev;
        };

        runtime = lib.mkRuntime {
          name = "ghcr.io/my-org/my-project/runtime";
          packages = sets.base ++ sets.python;
        };
      };
    };
}
```

2. Build your images:
```bash
nix build .#devcontainer
nix build .#runtime
```

3. Load into Docker:
```bash
docker load < result
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  flake.nix (single source of truth)                                 │
│                                                                     │
│  nixpkgs pinned @ nixpkgs-unstable (weekly updates via CI)          │
│                                                                     │
│  Package Sets:                    Builder Functions:                │
│  ├── base                         ├── mkDevContainer { packages }   │
│  ├── devTools                     └── mkRuntime { packages }        │
│  ├── nixTools                                                       │
│  ├── python, pythonDev                                              │
│  ├── node, nodeDev                                                  │
│  ├── go, goDev                                                      │
│  └── rust, rustDev                                                  │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ inputs.nixpkgs.follows = "infra/nixpkgs"
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  project/flake.nix                                                  │
│                                                                     │
│  packages = sets.base ++ sets.python ++ sets.pythonDev;            │
│                                                                     │
│  devcontainer = infra.lib.mkDevContainer { inherit packages; };    │
│  runtime = infra.lib.mkRuntime { packages = sets.base ++ python; };│
└─────────────────────────────────────────────────────────────────────┘
```

## Package Sets

| Set | Contents |
|-----|----------|
| `base` | bash, coreutils, findutils, grep, sed, cacert, tzdata |
| `devTools` | git, curl, jq, ripgrep, fd, fzf, bat, shadow, sudo |
| `nixTools` | nix, direnv, nix-direnv |
| `python` | python312 |
| `pythonDev` | pip, virtualenv, uv, ruff, pyright |
| `node` | nodejs_22 |
| `nodeDev` | bun, typescript, prettier, eslint |
| `go` | go |
| `goDev` | gopls, golangci-lint |
| `rust` | rustc, cargo |
| `rustDev` | rust-analyzer, clippy, rustfmt |

## Builder Functions

### mkDevContainer

Creates a development container with:
- vscode user (uid 1000) with sudo access
- direnv hook in bashrc
- Nix configured for flakes

```nix
lib.mkDevContainer {
  name = "ghcr.io/org/project/devcontainer";
  packages = sets.base ++ sets.devTools ++ sets.python;
  # Optional:
  user = "vscode";  # default
  extraConfig = {};  # additional Docker config
}
```

### mkRuntime

Creates a minimal production container with:
- app user (uid 1000, non-root)
- No development tools
- No Nix

```nix
lib.mkRuntime {
  name = "ghcr.io/org/project/runtime";
  packages = sets.base ++ sets.python;
  # Optional:
  user = "app";      # default
  workdir = "/app";  # default
  extraConfig = {};  # additional Docker config
}
```

## Docker Layer Sharing

All projects using `nixpkgs.follows = "infra/nixpkgs"` get **identical store paths** for shared packages. This means:

- Python in Project A = `/nix/store/xyz-python312`
- Python in Project B = `/nix/store/xyz-python312` (same hash!)
- Docker layers containing these paths are **shared**

Result: Only project-specific packages are downloaded when pulling images.

## Overlays

Custom Nix overlays in `overlays/`:

- `cve-patches.nix` - Security patches for Critical/High CVEs
- `license-fixes.nix` - Recompile to avoid copyleft
- `custom-builds.nix` - Custom compilation flags

## CI Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| build-containers | Push to main | Build example container images |
| security-scan | Daily + main | OSV CVE scanning |
| update-nixpkgs | Weekly | Automated flake.lock updates |

## Local Development

For local development without containers:

```bash
cd your-project
direnv allow
# Nix devShell activates automatically
```

Or explicitly:

```bash
nix develop
```

## Building Containers Locally on macOS (M2/ARM64)

To build `aarch64-linux` containers locally on M2 Mac with native performance, we use **Colima** - a lightweight container runtime that provides both Docker and a Linux VM.

### Prerequisites

1. **Install Colima:**
   ```bash
   brew install colima docker
   ```

2. **Create the Nix builder VM:**
   ```bash
   ./scripts/colima-vm create
   ```

### Building Containers

Use the `build-in-colima` script:

```bash
# Build and push to Cachix (default)
./scripts/build-in-colima laingville-devcontainer local
./scripts/build-in-colima example-python-runtime dev

# Build without pushing (for quick iteration)
./scripts/build-in-colima --no-push laingville-devcontainer local
```

The script:
1. Configures Cachix in the VM using your macOS credentials
2. Builds the container inside the Colima VM (native aarch64-linux)
3. Pulls dependencies from `cache.nixos.org` + `mrdavidlaing.cachix.org`
4. Pushes custom packages to Cachix (for faster future builds)
5. Streams the result back to macOS
6. Loads it into Docker and tags it

### Using the Built Image

```bash
# Run the container
docker run --rm -it ghcr.io/mrdavidlaing/laingville-devcontainer-nix/laingville-devcontainer:local bash

# Use in devcontainer.json
{
  "image": "ghcr.io/mrdavidlaing/laingville-devcontainer-nix/laingville-devcontainer:local"
}
```

### Managing the VM

```bash
./scripts/colima-vm status   # Check status
./scripts/colima-vm stop     # Stop VM (preserves data)
./scripts/colima-vm start    # Start VM
./scripts/colima-vm ssh      # SSH into VM
./scripts/colima-vm delete   # Delete VM completely
```

### Cachix Binary Cache

The build script uses Cachix to cache and share Nix build artifacts:

| Cache | Purpose |
|-------|---------|
| `cache.nixos.org` | Standard nixpkgs packages |
| `mrdavidlaing.cachix.org` | Custom packages (devcontainer layers, etc.) |

**Setup (one-time on macOS):**
```bash
nix profile install nixpkgs#cachix
cachix authtoken <your-token>
cachix use mrdavidlaing
```

The build script reads your credentials from `~/.config/cachix/cachix.dhall` and configures the VM automatically.

**For cache hits on custom packages**, commit your changes before building - a dirty Git tree changes derivation hashes.

### Why Colima?

- **Native ARM64**: Uses Apple Virtualization framework for native aarch64-linux performance
- **Docker replacement**: Can replace Docker Desktop entirely (free, MIT licensed)
- **Unified solution**: Same VM for Docker runtime and Nix builds
- **Filesystem mount**: macOS filesystem is mounted at the same paths inside the VM

### Note

The GitHub Actions workflow builds containers on Linux runners for CI/CD. The local Colima setup is for fast iteration during development.
