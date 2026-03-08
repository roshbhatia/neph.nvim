## Why

The per-agent JSON history persistence in `internal/history.lua` is redundant — every AI agent (Claude, Pi, Gemini, etc.) maintains its own conversation history with richer context than neph could ever capture. Neph's history only records prompts sent through the neph input UI, missing agent-initiated turns entirely. It's always stale and incomplete.

The only valuable piece is `terminal.lua`'s `last_prompt` for the "resend" feature, which is in-memory and doesn't need persistence.

## What Changes

- Remove `internal/history.lua` (JSON file persistence, vim.ui.select picker, index tracking)
- Remove `M.history()` from `api.lua`
- Remove history-related keymaps
- Keep `internal/terminal.lua` with `get_last_prompt`/`set_last_prompt` (in-memory only)
- Keep `M.resend()` in `api.lua` (uses terminal.lua, not history.lua)
- Clean up any references in init.lua, config.lua, or tests

## Capabilities

### Removed Capabilities
- `prompt-history`: Per-agent JSON history persistence and picker UI

## Impact

- **internal/history.lua**: Delete entirely
- **api.lua**: Remove `M.history()`, remove `require("neph.internal.history")`
- **init.lua**: Remove history-related keymap registration if any
- **tests/history_spec.lua**: Delete or reduce to terminal.lua tests only
- **internal/terminal.lua**: Unchanged (already minimal)
- **No CLI changes**
