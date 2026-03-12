## Why

Audit rounds 1–7 hardened individual code paths, but a broader sweep reveals two classes of remaining issues: (1) dead references and broken wiring inside the review system (phantom `:NephReviewPost` command, config reads from wrong source, missing `request_id` propagation), and (2) multi-session safety gaps where two Neovim instances in different directories can collide on socket discovery, tool installation, and debug logging.

## What Changes

- **Fix dead `:NephReviewPost` reference** — replace misleading notification with accurate "review queued" message
- **Wire `request_id` through review UI** — error recovery in `ui.lua` currently passes `""` to `review_queue.on_complete()`, preventing proper dequeue of the next review
- **Fix config source in review UI** — keymaps and signs read from `vim.g.neph_config` instead of `require("neph.config").current`, ignoring user setup opts
- **Add `bus.register` to `protocol.json`** — method exists in rpc dispatch but is missing from the contract
- **Fix CLI socket discovery for multi-instance** — single-instance fast path skips cwd check; multiple instances with same git root pick non-deterministically
- **Add file lock to tool installation** — concurrent `setup()` calls from multiple instances can race on the shared fingerprint manifest and corrupt builds
- **Scope debug log per instance** — all instances append to `/tmp/neph-debug.log` without locking, interleaving output

## Capabilities

### New Capabilities

- `instance-isolation`: Guards for multi-Neovim-instance safety — socket discovery tiebreaking, tool install locking, per-instance debug logs

### Modified Capabilities

- `review-ui`: Fix config source (vim.g → config module), wire request_id through ui_state, fix notification text
- `rpc-dispatch`: Add `bus.register` to protocol.json contract
- `tool-install`: Add inter-process locking to prevent concurrent build corruption
- `debug-logging`: Scope log path per Neovim PID to prevent interleaved writes

## Impact

- `lua/neph/internal/fs_watcher.lua` — notification text change
- `lua/neph/api/review/ui.lua` — config source fix, request_id propagation
- `lua/neph/api/review/init.lua` — pass request_id to ui_state
- `protocol.json` — add bus.register method
- `tools/neph-cli/src/transport.ts` — socket discovery tiebreaking
- `lua/neph/tools.lua` — file-based lock for concurrent install prevention
- `lua/neph/internal/log.lua` — per-PID log path
