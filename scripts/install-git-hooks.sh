#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

git config --local core.hooksPath .githooks
echo "Installed the repository pre-commit safety checks."
