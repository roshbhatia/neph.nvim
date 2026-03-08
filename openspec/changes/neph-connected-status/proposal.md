## Why

When hook-based agents (Claude, Gemini, Copilot, Cursor) are running, the gate CLI connects to Neovim via socket to run review flows. But there's no way for users to know if a neph-enabled agent is actively connected. Users want to show connection state in their statusline (e.g. lualine, heirline).

Currently each agent sets `vim.g.{agent}_active` but there's no unified "neph is connected and working" signal.

## What Changes

- Gate CLI sets `vim.g.neph_connected = true` at the start of any gate invocation
- Gate CLI unsets `vim.g.neph_connected` on cleanup (after review completes or on error)
- The `neph review` command also sets/unsets `neph_connected`
- Extension agents (pi) already set their own status; `neph_connected` covers the hook-based path
- Document the available `vim.g` variables for statusline integration

## Capabilities

### New Capabilities
- `neph-connected-status`: Unified `vim.g.neph_connected` flag for statusline consumption

## Impact

- **tools/neph-cli/src/gate.ts**: Set/unset `neph_connected` around the review flow
- **tools/neph-cli/src/index.ts**: Set/unset `neph_connected` for the `review` command
- **Tests**: Add gate test cases verifying `neph_connected` is set/unset
- **No Lua changes** (vim.g manipulation happens via existing RPC `status.set`/`status.unset`)
