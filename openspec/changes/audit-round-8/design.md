## Context

Audit round 8 identified 8 issues across two categories: dead references/broken wiring in the review system, and multi-session safety gaps. The review UI reads config from the wrong source, references a non-existent command, and doesn't propagate `request_id` through error paths. The CLI socket discovery has ambiguity with multiple Neovim instances, tool installation has no inter-process locking, and debug logging collides across instances.

## Goals / Non-Goals

**Goals:**
- Fix all review UI wiring issues (config source, request_id propagation, notification text)
- Make CLI socket discovery deterministic when multiple Neovim instances exist
- Prevent concurrent tool installation from corrupting build artifacts
- Scope debug logs per Neovim instance to prevent interleaved writes
- Add `bus.register` to protocol.json

**Non-Goals:**
- Full instance registry or session ID system (too much infrastructure for the current issues)
- Deduplicating fs_watcher triggers across instances (low severity, non-destructive)
- Zellij FIFO PID race (extremely unlikely in practice)

## Decisions

### 1. Review UI config source: use `require("neph.config").current`

**Choice:** Replace all `vim.g.neph_config` reads in `review/ui.lua` with `require("neph.config").current`.

**Why not vim.g?** The config module is the canonical source set during `setup()`. `vim.g.neph_config` is never populated by the plugin — it only exists if a user manually sets it, which is undocumented behavior.

### 2. Pass request_id through ui_state

**Choice:** Add `request_id` to the options table passed to `ui.open_diff_tab()` and store it on `ui_state`. The error handler in `ui.lua:346` already reads `ui_state.request_id` — it just needs to be set.

**Alternative considered:** Store request_id in a closure capture. Rejected because ui_state is already the state carrier and the field is already referenced.

### 3. Fix notification text, don't add :NephReviewPost command

**Choice:** Change fs_watcher notification from "use :NephReviewPost to review" to "opening review" (immediate) or "review queued (N pending)" (queued). No new user command.

**Why:** The review auto-opens via the queue. A manual command has no clear use case — by the time you'd use it, the review is already queued or the buffer/disk have converged.

### 4. Socket discovery: prefer exact cwd match, warn on ambiguity

**Choice:** When multiple candidates exist:
1. Exact cwd match → return it
2. cwd-is-subdirectory match → return it (existing behavior)
3. Git root match with single candidate → return it
4. Git root match with multiple candidates → log warning, return null (force explicit `NVIM_SOCKET_PATH`)

**Why not just always require explicit socket?** Single-instance and single-git-root cases are the 95% path. Breaking those would be a terrible UX regression. The fix targets only the ambiguous case (multiple instances, same git root).

### 5. Tool install locking: advisory lock file with PID

**Choice:** Before reading the manifest + building, acquire a lock at `<state_dir>/neph/install.lock` containing the PID. Use `vim.uv.fs_open` with exclusive create flag (`O_CREAT | O_EXCL`) for atomicity. If the lock exists and the PID is alive, skip the build. If the PID is stale (process dead), break the lock and retry.

**Why not flock/fcntl?** LuaJIT doesn't expose POSIX file locks without FFI. A PID-based lock file with staleness detection is simpler and sufficient — tool installation is infrequent and idempotent.

**Lock scope:** Per-agent-name, not global. Two instances installing different agents don't conflict.

### 6. Debug log: append PID to filename

**Choice:** Change log path from `/tmp/neph-debug.log` to `/tmp/neph-debug-<PID>.log`. Update `:NephDebug tail` to open the PID-scoped file. Update `:NephDebug on` to truncate only the PID-scoped file.

**Why not a shared log with locking?** Locking every log write adds latency to a hot path. Per-PID files are zero-contention and trivially correct. The TS side already has `process.pid` available.

**Migration:** The hardcoded path `/tmp/neph-debug.log` appears in the debug-logging spec. The TS `log.ts` module also writes to this path and will need updating.

### 7. Protocol.json: add bus.register

**Choice:** Add `bus.register` with its params to protocol.json. This is a straightforward spec-contract alignment — the method already exists in the dispatch table.

## Risks / Trade-offs

- **[Lock file left behind on crash]** → Mitigated by PID staleness check: if the owning process is dead, the lock is broken automatically.
- **[Per-PID log files accumulate]** → Low risk: debug mode is opt-in and files are in /tmp (cleared on reboot). Could add cleanup logic later.
- **[Socket discovery null return]** → The CLI already handles null by printing a clear error asking the user to set `NVIM_SOCKET_PATH`. This is the correct behavior for an ambiguous case.
- **[Config source change breaks users reading vim.g.neph_config]** → Unlikely: this was never documented or intentional. If someone relies on it, they can use `require("neph.config").current` instead.
