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

# ── Auto-install agent tools for detected CLIs ────────────────────────────────
# For each agent CLI found on PATH, install the corresponding neph integration.
# Plugin-based agents (amp, pi): install symlinks directly.
# Hook-based agents with global configs (gemini, cursor, codex): use neph install.
# Per-project-only agents (claude, opencode, copilot): print a hint.

NEPH_BIN="$HOME/.local/bin/neph"
INSTALLED_ANY=false

# amp: plugin symlink into ~/.config/amp/plugins/
if command -v amp &>/dev/null; then
  AMP_PLUGINS="$HOME/.config/amp/plugins"
  PLUGIN_SRC="$REPO_ROOT/tools/amp/neph-plugin.ts"
  PLUGIN_DST="$AMP_PLUGINS/neph-plugin.ts"
  mkdir -p "$AMP_PLUGINS"
  if [[ ! -L "$PLUGIN_DST" ]] || [[ "$(readlink "$PLUGIN_DST" 2>/dev/null)" != "$PLUGIN_SRC" ]]; then
    ln -sf "$PLUGIN_SRC" "$PLUGIN_DST"
    echo "neph build: installed amp plugin → $PLUGIN_DST"
    INSTALLED_ANY=true
  fi
fi

# Global hook agents: install into ~/.agent/ config if CLI is detected
if [[ -x "$NEPH_BIN" ]]; then
  for agent in gemini cursor codex claude; do
    if command -v "$agent" &>/dev/null; then
      output="$("$NEPH_BIN" install "$agent" 2>&1)"
      if [[ -n "$output" ]]; then
        echo "neph build: $output"
      fi
      INSTALLED_ANY=true
    fi
  done
fi

# Per-project-only agents: print hint if detected but not auto-installable globally
HINT_AGENTS=()
for agent in opencode pi; do
  if command -v "$agent" &>/dev/null; then
    HINT_AGENTS+=("$agent")
  fi
done
if [[ ${#HINT_AGENTS[@]} -gt 0 ]]; then
  echo "neph build: detected ${HINT_AGENTS[*]} — run 'neph integration toggle <agent>' in each project"
fi

echo "neph build: done"
