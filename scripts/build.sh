#!/usr/bin/env bash
# Build all neph.nvim TypeScript tool packages and install the CLI symlink.
# Usage: bash scripts/build.sh [--no-install]
#
# Options:
#   --no-install   Skip creating the ~/.local/bin/neph symlink
#
# Exit codes:
#   0  All packages built (and symlink installed unless --no-install)
#   1  Dependency missing (npm not found)
#   2  One or more package builds failed

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SYMLINK=true

for arg in "$@"; do
  case "$arg" in
    --no-install) INSTALL_SYMLINK=false ;;
  esac
done

# ── Dependency check ──────────────────────────────────────────────────────────
if ! command -v npm &>/dev/null; then
  echo "neph build: ERROR — 'npm' not found on PATH." >&2
  echo "  Install Node.js (https://nodejs.org) and re-run :NephBuild or 'bash scripts/build.sh'." >&2
  exit 1
fi

echo "neph build: using $(npm --version | tr -d '\n') ($(node --version | tr -d '\n'))"

# ── Build each package ────────────────────────────────────────────────────────
PACKAGES=(
  "tools/neph-cli"
  "tools/amp"
  "tools/pi"
)

FAILED=()
for pkg in "${PACKAGES[@]}"; do
  dir="$REPO_ROOT/$pkg"
  if [[ ! -f "$dir/package.json" ]]; then
    echo "neph build: skipping $pkg (no package.json)"
    continue
  fi
  echo "neph build: building $pkg …"
  if (cd "$dir" && npm ci --silent 2>&1 && npm run build --silent 2>&1); then
    echo "neph build: ✓ $pkg"
  else
    echo "neph build: ✗ $pkg FAILED" >&2
    FAILED+=("$pkg")
  fi
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "neph build: ERROR — failed packages: ${FAILED[*]}" >&2
  exit 2
fi

# ── Install CLI symlink ───────────────────────────────────────────────────────
if [[ "$INSTALL_SYMLINK" == "true" ]]; then
  CLI_SRC="$REPO_ROOT/tools/neph-cli/dist/index.js"
  CLI_DST="$HOME/.local/bin/neph"
  mkdir -p "$(dirname "$CLI_DST")"
  ln -sf "$CLI_SRC" "$CLI_DST"
  echo "neph build: symlinked ~/.local/bin/neph → $CLI_SRC"
fi

echo "neph build: done"
