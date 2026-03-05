## 1. Config: rename `"native"` → `"snacks"`, simplify `file_refresh`

- [x] 1.1 In `lua/neph/config.lua`: change `multiplexer = nil` default → `multiplexer = "snacks"`; update the `---@field multiplexer?` annotation to list `"snacks"|"wezterm"|"tmux"|"zellij"` (drop `"native"` and `nil`)
- [x] 1.2 In `lua/neph/config.lua`: simplify `neph.FileRefreshConfig` — remove `timer_interval?` and `updatetime?` fields from the `---@class` annotation; update `file_refresh` default to `{ enable = true }` (no `timer_interval`/`updatetime` keys)

## 2. Session: simplify `detect_backend()`

- [x] 2.1 In `lua/neph/internal/session.lua`: replace `detect_backend()` body with `return config.multiplexer or "snacks"` — delete the SSH_CONNECTION and WEZTERM_PANE env-var heuristics
- [x] 2.2 In `lua/neph/internal/session.lua`: update the backend selection block — replace the `else` (native) fallback label comment with `-- "snacks"` and ensure `elseif btype == "snacks"` or `else` maps to `require("neph.internal.backends.native")`

## 3. `file_refresh.lua`: hardcode timer values

- [x] 3.1 In `lua/neph/internal/file_refresh.lua`: change timer and updatetime reads to `opts.timer_interval or 1000` and `opts.updatetime or 750` (backward-compat); they are no longer part of the public config but still work if passed

## 4. Fix `LUA_PREVIEW` in `shim.py`

- [x] 4.1 In `tools/core/shim.py` `LUA_PREVIEW`: add `local ESC = '\27'` near the top of the Lua string (before the `while not done` loop)
- [x] 4.2 Verify `lua/neph/internal/backends/native.lua` `M.open()` still passes `NVIM_SOCKET_PATH = vim.env.NVIM_SOCKET_PATH` in the `env` table — restore it if missing
- [x] 4.3 Smoke-test `shim preview <file>` from a terminal inside Neovim: confirm vimdiff opens, keypress `y`/`n` works, and JSON result is printed; confirm ESC / `d` triggers the reject path

## 5. README overhaul

- [x] 5.1 In `README.md` Configuration section: update multiplexer docs — `"snacks"` is the default value and the correct label; remove `nil` / auto-detect description; add WezTerm opt-in note
- [x] 5.2 In `README.md` Configuration section: remove `timer_interval` and `updatetime` from the `file_refresh` example block; keep only `enable`
- [x] 5.3 In `README.md` Companion Tools table: remove the `tools/core/nvim-shim` row
- [x] 5.4 Add a new **Socket Integration** section to `README.md` explaining: what `NVIM_SOCKET_PATH` is, how to enable it (`nvim --listen /tmp/nvim.sock` or `:lua vim.fn.serverstart(...)` in init), that neph auto-forwards it to agent terminals, and what it unlocks (shim RPC + vimdiff hunk review in pi.ts)

## 6. Tests

- [x] 6.1 In `tests/config_spec.lua` (or equivalent): update assertion to expect `multiplexer = "snacks"` in `config.defaults`
- [x] 6.2 In `tests/config_spec.lua`: add assertion that `config.defaults.file_refresh` does NOT contain `timer_interval` or `updatetime` keys
- [x] 6.3 Run `task test` from repo root and confirm all tests pass
