## 1. Review UI Wiring Fixes

- [x] 1.1 In `lua/neph/api/review/ui.lua`, replace all `vim.g.neph_config` reads with `require("neph.config").current` for keymaps and signs
- [x] 1.2 In `lua/neph/api/review/init.lua`, pass `request_id` into the options for `ui.open_diff_tab()` and store it on `ui_state`
- [x] 1.3 In `lua/neph/internal/fs_watcher.lua:132`, change notification from "use :NephReviewPost to review" to "opening review" or "review queued" depending on queue state

## 2. Protocol Contract

- [x] 2.1 Add `bus.register` method with params `["agent", "channel_id"]` to `protocol.json`
- [x] 2.2 Verify contract test passes (`tests/contract_spec.lua`)

## 3. CLI Socket Discovery

- [x] 3.1 In `tools/neph-cli/src/transport.ts`, refactor git-root fallback to count matching candidates — return socket only if exactly one matches, return null if ambiguous
- [x] 3.2 Add transport tests for ambiguous multi-instance scenarios in `tools/neph-cli/tests/transport.test.ts`

## 4. Tool Install Locking

- [x] 4.1 Add `acquire_lock(name)` and `release_lock(name)` helpers to `lua/neph/tools.lua` using PID-based lock files at `<state_dir>/neph/install-<name>.lock`
- [x] 4.2 Add stale lock detection (check if PID is alive via `vim.uv.kill(pid, 0)`)
- [x] 4.3 Wrap `run_build` and `run_build_sync` calls in lock acquire/release
- [x] 4.4 Ensure lock is released in all exit paths (success, failure, error)

## 5. Per-Instance Debug Logging

- [x] 5.1 In `lua/neph/internal/log.lua`, change `LOG_PATH` from `/tmp/neph-debug.log` to `/tmp/neph-debug-<PID>.log` using `vim.fn.getpid()`
- [x] 5.2 Update `:NephDebug on` truncation and `:NephDebug tail` to use PID-scoped path
- [x] 5.3 In `tools/lib/log.ts`, change log path to `/tmp/neph-debug-${process.ppid}.log` to write to the parent Neovim's log file
