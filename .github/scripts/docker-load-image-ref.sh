#!/usr/bin/env bash
#
# docker-load-image-ref.sh
#
# Load a Docker image tarball (as produced by `nix build ...` for dockerTools images)
# and print the loaded image reference (repo:tag) to stdout.
#
# Usage:
#   bash .github/scripts/docker-load-image-ref.sh <tar_path>
#
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <tar_path>" >&2
  exit 2
fi

TAR_PATH="$1"

if [ ! -f "$TAR_PATH" ]; then
  echo "error: tarball not found: $TAR_PATH" >&2
  exit 2
fi

LOAD_OUTPUT="$(docker load < "$TAR_PATH")"
echo "$LOAD_OUTPUT"

# docker load output is typically:
#   Loaded image: <repo>:<tag>
IMAGE_REF="$(echo "$LOAD_OUTPUT" | sed -n 's/^Loaded image: //p' | tail -n 1)"

if [ -z "$IMAGE_REF" ]; then
  echo "error: could not determine loaded image ref from docker load output" >&2
  exit 1
fi

echo "$IMAGE_REF"
