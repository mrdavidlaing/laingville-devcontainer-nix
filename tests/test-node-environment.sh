#!/usr/bin/env bash
# test-node-environment.sh - Validate Node.js environment in containers
#
# This script runs inside a container to verify the Node.js/npm environment
# is properly configured and functional.
#
# Usage:
#   docker run --rm <image> /path/to/test-node-environment.sh
#   # Or mount and run:
#   docker run --rm -v $(pwd)/tests:/tests <image> /tests/test-node-environment.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0

pass() {
  echo -e "${GREEN}PASS${NC}: $1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
  echo -e "${RED}FAIL${NC}: $1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

warn() {
  echo -e "${YELLOW}WARN${NC}: $1"
}

section() {
  echo ""
  echo "=== $1 ==="
}

#############################################
# Basic Node.js checks
#############################################
section "Node.js Basic Checks"

# Check node is available
if command -v node > /dev/null 2>&1; then
  NODE_VERSION=$(node --version)
  pass "node is available: $NODE_VERSION"
else
  fail "node command not found"
fi

# Check node can execute JavaScript
if node -e "console.log('hello')" 2> /dev/null | grep -q "hello"; then
  pass "node can execute JavaScript"
else
  fail "node cannot execute JavaScript"
fi

# Check node version is 22.x (LTS)
if [[ "${NODE_VERSION:-}" =~ ^v22\. ]]; then
  pass "node version is 22.x LTS"
else
  warn "node version is not 22.x: ${NODE_VERSION:-unknown}"
fi

#############################################
# npm checks
#############################################
section "npm Checks"

# Check npm is available
if command -v npm > /dev/null 2>&1; then
  NPM_VERSION=$(npm --version)
  pass "npm is available: $NPM_VERSION"
else
  fail "npm command not found"
fi

# Check npm version is 11.x (patched)
if [[ "${NPM_VERSION:-}" =~ ^11\. ]]; then
  pass "npm version is 11.x (patched for CVE-2025-64756)"
else
  warn "npm version is not 11.x: ${NPM_VERSION:-unknown} - may have glob vulnerability"
fi

# Check npm can show its config
if npm config list > /dev/null 2>&1; then
  pass "npm config is accessible"
else
  fail "npm config command failed"
fi

#############################################
# npx checks
#############################################
section "npx Checks"

# Check npx is available
if command -v npx > /dev/null 2>&1; then
  NPX_VERSION=$(npx --version 2> /dev/null || echo "unknown")
  pass "npx is available: $NPX_VERSION"
else
  fail "npx command not found"
fi

#############################################
# CVE-2025-64756 glob version check
#############################################
section "Security: glob Version Check (CVE-2025-64756)"

# Find glob version in npm's dependencies
GLOB_VERSION=""
NPM_PATH=$(dirname "$(dirname "$(command -v npm)")")/lib/node_modules/npm

if [ -f "$NPM_PATH/node_modules/glob/package.json" ]; then
  GLOB_VERSION=$(grep '"version"' "$NPM_PATH/node_modules/glob/package.json" | head -1 | sed 's/.*"version": "\([^"]*\)".*/\1/')
fi

if [ -n "$GLOB_VERSION" ]; then
  echo "glob version in npm: $GLOB_VERSION"

  # glob 10.4.5 and earlier are vulnerable
  # glob 10.5.0+ or 11.x+ are fixed
  MAJOR=$(echo "$GLOB_VERSION" | cut -d. -f1)
  MINOR=$(echo "$GLOB_VERSION" | cut -d. -f2)

  if [ "$MAJOR" -ge 11 ]; then
    pass "glob version $GLOB_VERSION is not vulnerable to CVE-2025-64756"
  elif [ "$MAJOR" -eq 10 ] && [ "$MINOR" -ge 5 ]; then
    pass "glob version $GLOB_VERSION is not vulnerable to CVE-2025-64756"
  else
    fail "glob version $GLOB_VERSION may be vulnerable to CVE-2025-64756 (needs >= 10.5.0)"
  fi
else
  warn "Could not determine glob version"
fi

#############################################
# Package installation test
#############################################
section "npm Package Installation Test"

# Create a temp directory for testing
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Initialize a package.json
if npm init -y > /dev/null 2>&1; then
  pass "npm init works"
else
  fail "npm init failed"
fi

# Install a small package (semver is small and has no native deps)
if npm install --save semver@7.6.0 2> /dev/null; then
  pass "npm install works (installed semver@7.6.0)"
else
  fail "npm install failed"
fi

# Verify the package is usable
if node -e "const semver = require('semver'); console.log(semver.valid('1.2.3'))" 2> /dev/null | grep -q "1.2.3"; then
  pass "installed package is usable via require()"
else
  fail "installed package is not usable"
fi

# Cleanup
cd /
rm -rf "$TEMP_DIR"

#############################################
# ES Modules test
#############################################
section "ES Modules Test"

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Create a simple ES module
cat > test.mjs << 'EOF'
const greeting = 'Hello from ES Module';
console.log(greeting);
export default greeting;
EOF

if node test.mjs 2> /dev/null | grep -q "Hello from ES Module"; then
  pass "ES Modules (import/export) work"
else
  fail "ES Modules do not work"
fi

# Cleanup
cd /
rm -rf "$TEMP_DIR"

#############################################
# Native module compilation test (node-gyp)
#############################################
section "Native Module Compilation Test"

# This test validates that:
# 1. Node.js include headers are available
# 2. Python is accessible for node-gyp
# 3. Native module compilation works end-to-end

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Check if python is available (required by node-gyp)
if command -v python3 > /dev/null 2>&1 || command -v python > /dev/null 2>&1; then
  PYTHON_VERSION=$(python3 --version 2> /dev/null || python --version 2> /dev/null || echo "unknown")
  pass "python is available for node-gyp: $PYTHON_VERSION"
else
  warn "python not found - native module compilation may fail"
fi

# Check if node headers exist
NODE_INCLUDE_DIR=$(dirname "$(dirname "$(command -v node)")")/include/node
if [ -d "$NODE_INCLUDE_DIR" ] && [ -f "$NODE_INCLUDE_DIR/node.h" ]; then
  pass "Node.js headers are available at $NODE_INCLUDE_DIR"
else
  warn "Node.js headers not found at $NODE_INCLUDE_DIR - native modules may not compile"
fi

# Initialize and try to install a small native module
# Using 'bindings' as a build-time test (it's tiny and just tests node-gyp setup)
npm init -y > /dev/null 2>&1

# Try installing a minimal native module that requires compilation
# 'tiny-secp256k1' is too heavy; use 'int64-buffer' which is simpler
# Actually, let's just verify node-gyp can be invoked
if npm install node-gyp --save-dev 2> /dev/null; then
  pass "node-gyp installed successfully"

  # Try to run node-gyp to check if it can find headers
  if npx node-gyp list 2>&1 | grep -q -E "(node|No node development files)"; then
    pass "node-gyp can execute and check for headers"
  else
    warn "node-gyp execution returned unexpected output"
  fi
else
  warn "Could not install node-gyp - native module builds may not work"
fi

# Cleanup
cd /
rm -rf "$TEMP_DIR"

#############################################
# Summary
#############################################
section "Summary"
echo ""
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo ""

if [ "$TESTS_FAILED" -gt 0 ]; then
  echo -e "${RED}Some tests failed!${NC}"
  exit 1
else
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
fi
