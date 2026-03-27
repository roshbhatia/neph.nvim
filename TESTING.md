# Testing Strategy

neph.nvim uses a two-tier test strategy: **unit tests** for isolated module behaviour and **integration tests** for paths that require real Neovim vim commands.

## Running Tests

```bash
# Full suite
nvim --headless -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/', {minimal_init='tests/minimal_init.lua', sequential=true})" \
  2>&1 | grep -E "Success|Failed|Errors" | sed 's/\x1b\[[0-9;]*m//g'

# Zero-failure check (CI gate)
nvim --headless -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/', {minimal_init='tests/minimal_init.lua', sequential=true})" \
  2>&1 | grep -E "Failed\s*:\s*[^0]|Errors\s*:\s*[^0]" | sed 's/\x1b\[[0-9;]*m//g'

# Lint
stylua --check lua/ tests/
```

Tests require Neovim ≥ 0.10 and [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) on the runtime path (bootstrapped by `tests/minimal_init.lua`).

---

## Tier 1 — Unit Tests

Unit tests run each module in isolation. Dependencies are replaced with lightweight stubs so tests stay fast (<1 ms each) and side-effect free.

| Module | Test file | What is stubbed |
|--------|-----------|-----------------|
| `review_queue` | `tests/review_queue_spec.lua` | `open_fn` (capture-only stub) |
| `gate` | `tests/gate_spec.lua` | nothing — pure state machine |
| `review_provider` | `tests/review_provider_spec.lua` | `agents` module |
| `integration` | `tests/integration_spec.lua` | `config` |
| `review engine` | `tests/api/review/engine_spec.lua` | nothing — pure Lua |
| `review/init` | `tests/api/review/init_spec.lua` | `engine`, `ui`, `review_queue`, `review_provider` |
| `rpc dispatch` | `tests/rpc_spec.lua` | all downstream handlers |
| `session` | `tests/session_spec.lua`, `session_boundary_spec.lua` | backend |
| `health` | `tests/health_spec.lua` | `vim.fn.executable`, `vim.fn.systemlist` |

**What unit tests can catch**: incorrect logic in an individual module, missing nil guards, wrong return shapes, state machine transitions.

**What unit tests cannot catch**: bugs in the interaction between modules, or bugs in Neovim vim command behaviour (e.g., `vim.cmd("tabnew")`, `nvim_buf_set_lines`, `diffthis`).

---

## Tier 2 — Integration Tests

Integration tests run real Neovim vim commands. They use only the minimum stubs needed to control inputs/outputs.

| File | What is NOT stubbed | What IS stubbed |
|------|--------------------|--------------------|
| `tests/api/review/ui_integration_spec.lua` | `open_diff_tab` (entire function) | nothing — real vim commands throughout |
| `tests/api/review/flow_integration_spec.lua` | `open_diff_tab`, `_open_immediate` | engine session (hunk count), review_provider |
| `tests/backend_integration_spec.lua` | backend module loading | `vim.fn.jobstart`, wezterm CLI calls |

### When to write an integration test

Write an integration test (not a unit test) when the bug you want to catch involves:

1. **Real Neovim API calls** — `vim.cmd`, `nvim_buf_set_lines`, `nvim_win_get_buf`, `diffthis`, etc.
2. **RPC-context vim commands** — code called from a Neovim RPC message handler where "current buffer/window" state may differ from interactive use.
3. **Cross-module wiring** — a chain where Module A calls Module B which calls vim API; stubbing B hides the bug.

**Concrete example — the "empty vimdiff tab" bug (fixed in commit 60d6f53):**

`open_diff_tab` used `vim.api.nvim_get_current_buf()` to find the buffer in the newly created tab. When called from a Neovim RPC handler (amp terminal → neph CLI → socket), the "current buffer" was stale and pointed to the terminal buffer. The new tab opened but its buffer was never populated — appearing empty.

All unit tests used `package.loaded["neph.api.review.ui"] = make_stub_ui()` which replaced `open_diff_tab` with `function() return { tab = 999 } end`. This made the bug invisible to CI for the entire time it existed.

The fix was to use `nvim_tabpage_get_win(tab)` + `nvim_win_get_buf()` instead. The integration test `ui_integration_spec.lua` (task 1.7) directly asserts the invariant: `ui_state.left_buf == nvim_win_get_buf(ui_state.left_win)`.

---

## Tab Teardown Pattern

Any test that calls `open_diff_tab` or `_open_immediate` with a 1+ hunk engine may open a new tab. Always close it in `after_each`:

```lua
local ui_state

after_each(function()
  if ui_state then
    pcall(ui.cleanup, ui_state)
    ui_state = nil
  end
end)
```

Or, when testing via `_open_immediate` (no direct `ui_state` handle):

```lua
local tab_before

before_each(function()
  tab_before = #vim.api.nvim_list_tabpages()
end)

after_each(function()
  local tabs = vim.api.nvim_list_tabpages()
  for _, tab in ipairs(tabs) do
    local nr = vim.api.nvim_tabpage_get_number(tab)
    if nr > tab_before then
      pcall(vim.cmd, "tabclose " .. nr)
    end
  end
end)
```

Use `pcall` for the close — if the test already failed and the tab is in a bad state, the `after_each` should not cascade a second failure.
