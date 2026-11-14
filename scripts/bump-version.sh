#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
node "$SCRIPT_DIR/bump-version.mjs" "${1:?Usage: scripts/bump-version.sh <version>}"
