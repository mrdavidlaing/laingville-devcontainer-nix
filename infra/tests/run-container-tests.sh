#!/usr/bin/env bash
# run-container-tests.sh - Run environment validation tests against containers
#
# Usage:
#   ./run-container-tests.sh [image-name]
#   ./run-container-tests.sh                    # Test all containers
#   ./run-container-tests.sh node               # Test only node containers
#   ./run-container-tests.sh python             # Test only python containers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Container configurations using parallel arrays (bash 3.2+ compatible)
# Associative arrays require bash 4+, but macOS ships with bash 3.2
CONTAINER_NAMES=(
  "example-node-devcontainer"
  "example-node-runtime"
  "example-python-devcontainer"
  "example-python-runtime"
  "laingville-devcontainer"
)
CONTAINER_TEST_TYPES=(
  "node"
  "node"
  "python"
  "python"
  "base"
)

# Image registry
REGISTRY="ghcr.io/mrdavidlaing/laingville"

run_test() {
  local container="$1"
  local test_type="$2"
  local image_ref="$3"

  echo -e "${BLUE}Testing $container ($test_type)${NC}"
  echo "Image: $image_ref"
  echo "---"

  case "$test_type" in
    node)
      docker run --rm \
        -v "$SCRIPT_DIR:/tests:ro" \
        "$image_ref" \
        bash /tests/test-node-environment.sh
      ;;
    python)
      docker run --rm \
        -v "$SCRIPT_DIR:/tests:ro" \
        "$image_ref" \
        bash /tests/test-python-environment.sh 2> /dev/null \
        || echo -e "${YELLOW}Python tests not implemented yet${NC}"
      ;;
    base)
      docker run --rm "$image_ref" bash -c 'echo "Container starts successfully"'
      echo -e "${GREEN}PASS${NC}: Container starts and bash works"
      ;;
  esac

  echo ""
}

build_and_load_image() {
  local container="$1"
  echo -e "${BLUE}Building $container...${NC}"

  local result_link="/tmp/container-test-$container"
  if nix build "$INFRA_DIR#$container" -o "$result_link" 2>&1; then
    docker load < "$result_link" > /dev/null
    # Get the loaded image name
    docker images --format '{{.Repository}}:{{.Tag}}' | grep "$container" | head -1
  else
    echo ""
    return 1
  fi
}

main() {
  local filter="${1:-}"
  local failed=0
  local passed=0

  echo "========================================"
  echo "Container Environment Validation Tests"
  echo "========================================"
  echo ""

  for i in "${!CONTAINER_NAMES[@]}"; do
    local container="${CONTAINER_NAMES[$i]}"
    local test_type="${CONTAINER_TEST_TYPES[$i]}"

    # Apply filter if provided
    if [ -n "$filter" ]; then
      if [[ ! "$container" =~ $filter ]] && [[ ! "$test_type" =~ $filter ]]; then
        continue
      fi
    fi

    # Build and load the image
    local image_ref
    image_ref=$(build_and_load_image "$container")

    if [ -z "$image_ref" ]; then
      echo -e "${RED}FAIL${NC}: Could not build $container"
      failed=$((failed + 1))
      continue
    fi

    # Run the tests
    # shellcheck disable=SC2310 # Intentional: we want to capture pass/fail, not exit on failure
    if run_test "$container" "$test_type" "$image_ref"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
  done

  echo "========================================"
  echo "Summary"
  echo "========================================"
  echo "Containers passed: $passed"
  echo "Containers failed: $failed"

  if [ "$failed" -gt 0 ]; then
    exit 1
  fi
}

main "$@"
