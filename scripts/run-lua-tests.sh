#!/usr/bin/env bash
# Run Lua test suite via plenary's busted runner.
# Sequential mode avoids parallel-job signal races that cause spurious exit-1.
PLENARY="${PLENARY_PATH:-${HOME}/.local/share/nvim/lazy/plenary.nvim}"
exec nvim --headless \
  --cmd 'set rtp+=.' \
  --cmd "set rtp+=${PLENARY}" \
  -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua', sequential=true}" \
  -c 'qa!'
