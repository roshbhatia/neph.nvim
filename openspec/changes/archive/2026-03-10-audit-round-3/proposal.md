## Why

Third-round e2e audit found 13 actionable bugs across the Lua and TypeScript codebases. The most critical are an operator-precedence bug in post-write review that will crash on partial merges, and JS `.replace()` only replacing the first occurrence in edit-tool reconstruction (silent data corruption). Remaining issues include timer resource leaks, missing timeouts on UI dialog promises, silent JSON parse failures, and missing bounds checks.

## What Changes

- Fix operator precedence bug in `review/init.lua:_apply_post_write` (`not x == y` → `x ~= y`)
- Fix `.replace()` first-occurrence-only in `gate.ts`, `opencode/edit.ts`, and `amp/neph-plugin.ts` — use `replaceAll()` or split/join
- Close debounce timers in `fs_watcher.lua` before nulling to prevent uv handle leaks
- Add timeout to `NephClient.uiSelect()` and `NephClient.uiInput()` (60s)
- Add error handler to `fs.watch()` calls in `gate.ts` and `index.ts`
- Add bounds check in `review/engine.lua` finalize to guard `new_lines[j]` access
- Add request body size limit (1MB) to `gemini/server.ts`
- Remove dead `unmap_keymaps` function in `review/ui.lua`
- Add notification when wezterm send-text job fails to start in `session.lua`

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `review-protocol`: Fix operator precedence in partial merge trailing-newline check; add bounds check in engine finalize
- `neph-cli`: Fix `.replace()` → `.replaceAll()` in gate edit reconstruction; add fs.watch error handler; add body size limit to companion server
- `gemini-companion-server`: Add HTTP request body size limit

## Impact

- `lua/neph/api/review/init.lua` — operator precedence fix
- `lua/neph/api/review/engine.lua` — bounds check on hunk line access
- `lua/neph/api/review/ui.lua` — dead code removal
- `lua/neph/internal/fs_watcher.lua` — timer close before nil
- `lua/neph/internal/session.lua` — wezterm job_id notification
- `tools/neph-cli/src/gate.ts` — replaceAll, fs.watch error handler
- `tools/neph-cli/src/index.ts` — fs.watch error handler
- `tools/opencode/edit.ts` — replaceAll
- `tools/amp/neph-plugin.ts` — replaceAll
- `tools/gemini/src/server.ts` — body size limit
- `tools/lib/neph-client.ts` — uiSelect/uiInput timeout
