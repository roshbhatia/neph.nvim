## Why

The `multiplexer` config uses `"native"` as the label for the snacks.nvim backend — a leaky internal name — and defaults to `nil` (auto-detect), which adds fragile env-var heuristics that rarely fire correctly. The `file_refresh` config exposes low-level timer knobs (`timer_interval`, `updatetime`) that aren't user-relevant. The vimdiff hunk-review workflow in `shim.py`/`pi.ts` is broken (likely a `getcharstr` deadlock when called back into the same Neovim instance from an in-process terminal). The README is out of date: it still mentions the removed `nvim-shim` bash wrapper, doesn't document the `NVIM_SOCKET_PATH` socket mechanism, and describes the old auto-detect default.

## What Changes

- **BREAKING** Rename `multiplexer = "native"` → `multiplexer = "snacks"` in config type, defaults, session backend selection, README, and tests
- Change `multiplexer` default from `nil` (auto-detect) to `"snacks"` — remove the auto-detect heuristic from `detect_backend()`
- Simplify `neph.FileRefreshConfig`: remove `timer_interval` and `updatetime` fields; keep only `enable` (internal defaults hardcoded in `file_refresh.lua`)
- Fix `LUA_PREVIEW` in `shim.py`: replace `vim.fn.getcharstr()` / `vim.fn.input()` with an approach that isn't subject to RPC re-entrancy deadlock
- Update `README.md`:
  - Remove `tools/core/nvim-shim` row from the Companion Tools table
  - Update multiplexer docs (`"snacks"` is now the value and the default)
  - Add **Socket integration** section documenting `NVIM_SOCKET_PATH`, how to enable it (`:listen` / `--listen`), and what it unlocks
  - Drop `timer_interval` / `updatetime` from the `file_refresh` config example

## Capabilities

### New Capabilities
- `socket-integration`: Documents and formalises the `NVIM_SOCKET_PATH` contract — Neovim exports it, neph.nvim forwards it to every agent terminal, and `shim`/`pi.ts` use it for RPC

### Modified Capabilities
- `multiplexer-config`: Rename `"native"` → `"snacks"`; change default from `nil` to `"snacks"`; remove auto-detect heuristic
- `config-module`: Drop `timer_interval` and `updatetime` from the public `neph.FileRefreshConfig` type
- `tool-install`: Remove reference to `tools/core/nvim-shim` (not auto-symlinked, no longer mentioned in README)

## Impact

- **`lua/neph/config.lua`** — rename `"native"` literal, remove `timer_interval`/`updatetime` from type and defaults
- **`lua/neph/internal/session.lua`** — `detect_backend()` simplified to check `config.multiplexer` and return it; default `"snacks"` replaces the `"native"` fallback; `elseif btype == "snacks"` replaces `else`
- **`lua/neph/internal/backends/native.lua`** — no rename needed (internal filename stays); `session.lua` maps `"snacks"` → native backend
- **`lua/neph/internal/file_refresh.lua`** — hardcode `timer_interval = 1000` and `updatetime = 750` internally; stop reading them from config
- **`tools/core/shim.py`** — rewrite `LUA_PREVIEW` to use `vim.ui.input` or a float/popup approach that avoids the `getcharstr` re-entrancy issue
- **`README.md`** — multiplexer section rewrite; remove nvim-shim row; add socket section
- **`tests/`** — update config test to assert `multiplexer = "snacks"` and absence of `timer_interval`/`updatetime` in `file_refresh`
