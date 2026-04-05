## Why

Six gaps surfaced during the post-audit agent compatibility review and the opencode.nvim investigation. Items 1–5 are small, high-confidence fixes that address real user-facing failure modes: Cupcake-dependent agents fail silently at the hook boundary if the binary isn't installed; the Cursor tools entry installs to the wrong path; build staleness checks are blind for amp and pi; test isolation leaks cause intermittent CI failures; and opencode is absent from `neph integration status` despite being a first-class agent.

Item 6 is the largest: adding SSE-driven review interception for opencode so the full neph review pipeline works without requiring Cupcake. This is the path to making opencode a zero-config agent.

## What Changes

### 1. Cupcake health check for harness agents

Add a check to `:checkhealth neph` that verifies `cupcake` is on PATH when any registered agent has `integration_group = "harness"`. Without this, users installing claude/cursor/opencode/pi get no feedback until a hook fires at runtime and fails with a cryptic error.

### 2. Remove incorrect `cursor` tools dst

`lua/neph/agents/cursor.lua` declares `dst = "~/.cursor/hooks.json"` (global home). Cursor loads hooks per-project; `neph integration toggle cursor` installs to `$CWD/.cursor/hooks.json`. The tools entry is both wrong (wrong path) and redundant (neph-cli is canonical for hook config). Remove the tools field from `cursor.lua`.

### 3. Fix `dist_is_current` stale detection for amp and pi

Both packages keep TypeScript source at the package root, not in `src/`. The current implementation scans `pkg_dir/src/` and returns `"current"` when no `.ts` files are found — meaning edits to `tools/amp/neph-plugin.ts` or `tools/pi/cupcake-harness.ts` never trigger a stale warning. Fix: fall back to scanning `pkg_dir/` root when `src/` is absent or empty.

### 4. Fix order-dependent test failures

Three tests fail when the full suite runs together but pass in isolation. Root cause is module state leaking between spec files via `package.loaded` (most likely `neph.api.review`, `neph.internal.gate`, or `neph.internal.review_queue` being left in a mutated state). Fix: identify which module(s) are leaking, add `package.loaded[...]= nil` teardown in `after_each` or add a `_reset()` call to the relevant modules.

### 5. opencode neph-cli integration entry

Add `opencode` to the `INTEGRATIONS` array in `tools/neph-cli/src/integration.ts`. Currently `neph integration status` is silent about opencode — it's the only agent whose Cupcake harness is installed via `cupcake init` rather than `neph integration toggle`, but we can still report its status (check whether `.cupcake/policies/opencode` exists in the project). No behaviour change, pure observability.

### 6. opencode SSE subscription for pre-write intercept

opencode exposes an HTTP REST + SSE server (`GET /event`) when launched with `--port`. The `permission.asked` event carries a full unified diff and a permission ID; responding to `POST /permission/<id>/reply` with `{ decision: "once" | "reject" }` accept/rejects the write before it hits disk. This makes the full neph review pipeline available for opencode without requiring the Cupcake harness.

The implementation has two parts:
- **Lua SSE client** (`lua/neph/internal/opencode_sse.lua`): subscribe to the opencode event stream via `vim.fn.jobstart({"curl", "-N", url})`, parse SSE lines, fire neph-internal events. Handle reconnect on job exit.
- **Permission bridge** (`lua/neph/reviewers/opencode_permission.lua`): listen for `permission.asked` with `permission == "edit"`, extract the diff, enqueue a neph review. On decision, POST to `/permission/<id>/reply`. Wire into the opencode agent's `integration_pipeline` as a review provider.

Server discovery borrows from opencode.nvim: `pgrep -f "opencode .*--port"` → extract port → confirm with `GET /session`.

The `file.edited` SSE event replaces `fs_watcher.lua` for opencode-triggered reloads (lower latency, no inotify handles, no epoch tracking needed).

## Capabilities

### New Capabilities

- `health-cupcake-check`: `:checkhealth neph` warns when harness agents are registered but `cupcake` is absent.
- `opencode-sse-client`: Lua SSE subscriber connecting to the running opencode HTTP server.
- `opencode-permission-review`: Pre-write review provider backed by opencode's permission API rather than a post-write fs hook.

### Modified Capabilities

- `agent-cursor`: Remove incorrect global tools dst; integration managed entirely by neph-cli.
- `tools-build-check`: `dist_is_current` falls back to package root scan when `src/` is absent.
- `integration-status`: opencode entry added to neph-cli INTEGRATIONS for status reporting.
- `test-suite`: Module teardown prevents state leakage between spec files.

## Impact

**Item 1**
- `lua/neph/health.lua` — add cupcake check in `check_agents()` or a new `check_deps()` helper

**Item 2**
- `lua/neph/agents/cursor.lua` — remove `tools` field

**Item 3**
- `lua/neph/internal/tools.lua` — `dist_is_current`: scan `pkg_dir/` when `pkg_dir/src/` has no `.ts` files

**Item 4**
- Investigation-first: identify leaking specs, then targeted `_reset()` / `package.loaded` teardown in affected spec `after_each` blocks

**Item 5**
- `tools/neph-cli/src/integration.ts` — add opencode entry to `INTEGRATIONS` with Cupcake-based status check

**Item 6**
- `lua/neph/internal/opencode_sse.lua` — new: SSE subscriber, server discovery, reconnect
- `lua/neph/reviewers/opencode_permission.lua` — new: permission bridge review provider
- `lua/neph/agents/opencode.lua` — wire new review provider; add `--port` arg handling
- `lua/neph/internal/integration.lua` — register new integration_group or override for opencode
- `tests/internal/opencode_sse_spec.lua` — new: SSE parse, server discovery, reconnect
- `tests/reviewers/opencode_permission_spec.lua` — new: permission bridge accept/reject flow
