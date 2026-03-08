## Architecture

Simple deletion. The dependency graph is:

```
api.lua ──→ history.lua  (M.history() calls history.pick())
api.lua ──→ terminal.lua (M.resend() calls terminal.get_last_prompt())
init.lua ──→ api.lua     (keymap for history)
```

After change:

```
api.lua ──→ terminal.lua (M.resend() unchanged)
```

## What Gets Deleted

1. **`lua/neph/internal/history.lua`** — entire file (120 lines)
   - `save()`, `load()`, `pick()`, `get_current_history_index()`, `set_current_history_index()`
   - JSON file I/O, vim.ui.select picker, index tracking

2. **`tests/history_spec.lua`** — entire file
   - Replace with minimal `terminal_spec.lua` testing `get_last_prompt`/`set_last_prompt`

3. **From `api.lua`**:
   - Remove `M.history()` function
   - Remove `require("neph.internal.history")`
   - Remove `history.save()` call in `input_for_active` if present

4. **From `init.lua`**:
   - Remove keymap binding for history (if `<leader>jh` or similar exists)

## What Stays

- **`lua/neph/internal/terminal.lua`** — 24 lines, untouched
  - `get_last_prompt(termname)` — returns in-memory last prompt
  - `set_last_prompt(termname, prompt)` — stores in-memory
- **`api.lua` `M.resend()`** — uses terminal.lua, not history.lua

## Testing

- Delete `tests/history_spec.lua`
- Add `tests/terminal_spec.lua` with:
  - `set_last_prompt` + `get_last_prompt` round-trip
  - `get_last_prompt` returns nil for unknown termname
  - Multiple agents maintain separate last prompts
- Verify existing tests still pass (no broken requires)
