# laingville-devcontainer-nix

Nix-based devcontainer infrastructure for building containerized development environments.

This repository contains:
- **infra/**: Nix flake with package sets and builder functions for creating devcontainers
- **.github/workflows/**: CI/CD workflows for building and scanning container images

## Quick Start

See [infra/README.md](infra/README.md) for detailed documentation on using this infrastructure in your projects.

## Building Containers

Containers are automatically built and published to GitHub Container Registry on pushes to `main`:

- `ghcr.io/mrdavidlaing/laingville-devcontainer-nix/laingville-devcontainer`
- `ghcr.io/mrdavidlaing/laingville-devcontainer-nix/example-python-devcontainer`
- `ghcr.io/mrdavidlaing/laingville-devcontainer-nix/example-python-runtime`
- `ghcr.io/mrdavidlaing/laingville-devcontainer-nix/example-node-devcontainer`
- `ghcr.io/mrdavidlaing/laingville-devcontainer-nix/example-node-runtime`

## CI/CD

- **Build Containers**: Builds multi-arch container images on push to main
- **Security Scan**: Daily security scanning with Trivy, Grype, and Vulnix
- **Update Nixpkgs**: Weekly automated updates of nixpkgs flake.lock
