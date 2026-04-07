#!/bin/bash
set -e

# Usage: compute-foundry-cache-restore-keys.sh <package_folder>
# Generates restore keys for Foundry cache (progressively shorter prefixes)

PACKAGE_FOLDER="${1}"

if [ -z "$PACKAGE_FOLDER" ]; then
  echo "Error: package_folder argument required" >&2
  exit 1
fi

# Compute hashes for each component
FOUNDRY_VERSION_HASH=$(sha256sum .github/actions/setup_deps/action.yml | cut -d' ' -f1)
SRC_HASH=$(find "${PACKAGE_FOLDER}/src" -name "*.sol" -type f 2>/dev/null | sort | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1 || echo "none")
TEST_HASH=$(find "${PACKAGE_FOLDER}/test" -name "*.sol" -type f 2>/dev/null | sort | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1 || echo "none")
SCRIPT_HASH=$(find "${PACKAGE_FOLDER}/script" -name "*.sol" -type f 2>/dev/null | sort | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1 || echo "none")
CONFIG_HASH=$(sha256sum "${PACKAGE_FOLDER}/foundry.toml" 2>/dev/null | cut -d' ' -f1 || echo "none")

# Generate progressively shorter restore keys (one per line)
echo "${PACKAGE_FOLDER}-${FOUNDRY_VERSION_HASH}-${SRC_HASH}-${TEST_HASH}-${SCRIPT_HASH}-${CONFIG_HASH}-"
echo "${PACKAGE_FOLDER}-${FOUNDRY_VERSION_HASH}-${SRC_HASH}-${TEST_HASH}-${SCRIPT_HASH}-"
echo "${PACKAGE_FOLDER}-${FOUNDRY_VERSION_HASH}-${SRC_HASH}-${TEST_HASH}-"
echo "${PACKAGE_FOLDER}-${FOUNDRY_VERSION_HASH}-${SRC_HASH}-"
echo "${PACKAGE_FOLDER}-${FOUNDRY_VERSION_HASH}-"
echo "${PACKAGE_FOLDER}-"
