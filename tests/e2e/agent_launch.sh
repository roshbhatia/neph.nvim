#!/usr/bin/env bash
# Per-agent launch tests. Each agent runs in its own nvim --headless instance.
# Skips agents not found on PATH. Exits non-zero if any installed agent fails.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCH_SCRIPT="$SCRIPT_DIR/launch_one.lua"

AGENTS=(claude pi copilot gemini amp opencode cursor goose codex crush)

passed=0
failed=0
skipped=0

for agent in "${AGENTS[@]}"; do
  cmd="$agent"
  case "$agent" in
    cursor) cmd="cursor-agent" ;;
  esac

  if ! command -v "$cmd" &>/dev/null; then
    echo "  ⊘ $agent (skipped: $cmd not on PATH)"
    skipped=$((skipped + 1))
    continue
  fi

  echo -n "  ● $agent ... "

  # Run in isolated nvim with 15s timeout
  if timeout 15 nvim --headless \
    --cmd 'set rtp+=.' \
    -l "$LAUNCH_SCRIPT" \
    -- "$agent" \
    2>&1; then
    echo "✓"
    passed=$((passed + 1))
  else
    exit_code=$?
    if [ $exit_code -eq 124 ]; then
      echo "✗ (timeout after 15s)"
    else
      echo "✗ (exit code $exit_code)"
    fi
    failed=$((failed + 1))
  fi
done

echo ""
echo "Agent launch: $passed passed, $failed failed, $skipped skipped"

if [ $failed -gt 0 ]; then
  exit 1
fi
