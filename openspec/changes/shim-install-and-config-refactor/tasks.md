## 1. Bundle Tools

- [x] 1.1 Copy `~/.local/bin/nvim-shim` → `tools/core/nvim-shim` and make it executable (`chmod +x`)
- [x] 1.2 Copy `~/.config/nvim/tools/shim.py` → `tools/core/shim.py`
- [x] 1.3 Copy `~/.config/nvim/tools/pi.ts` → `tools/pi/pi.ts`
- [x] 1.4 Add a brief `tools/README.md` explaining what each file is and how install/symlinks work

## 2. Config Module

- [x] 2.1 Create `lua/neph/config.lua` with the `defaults` table (keymaps, env, file_refresh, agents, multiplexer) and LuaDoc type annotations for `neph.Config` and `neph.FileRefreshConfig`
- [x] 2.2 Update `lua/neph/init.lua` to `require("neph.config")` and remove the local `defaults` table and type annotations
- [x] 2.3 Verify `M.setup(opts)` still merges opts correctly via `vim.tbl_deep_extend("force", require("neph.config").defaults, opts or {})`

## 3. Multiplexer Config

- [x] 3.1 Add `multiplexer?: "native"|"wezterm"|"tmux"|"zellij"|nil` to the `neph.Config` type in `config.lua`; default to `nil`
- [x] 3.2 Update `session.lua`'s `detect_backend()` to check `config.multiplexer` first — if set, return it directly (skip env-var heuristics)
- [x] 3.3 Create `lua/neph/internal/backends/tmux.lua` stub: `M.setup` emits `vim.notify` warning about stub; all interface methods (`open`, `focus`, `hide`, `show`, `is_visible`, `kill`, `cleanup_all`) are present and fall back / no-op gracefully
- [x] 3.4 Create `lua/neph/internal/backends/zellij.lua` stub: same structure as tmux stub
- [x] 3.5 Update `session.lua` backend selection to handle `"tmux"` and `"zellij"` by requiring their respective stub modules

## 4. Auto-Install Symlinks

- [x] 4.1 Add a `tools.install()` function in a new `lua/neph/tools.lua` module that symlinks `shim.py → ~/.local/bin/shim` and `pi.ts → ~/.pi/agent/extensions/nvim.ts` using `ln -sf`, creating parent directories with `vim.fn.mkdir(..., "p")`
- [x] 4.2 Source-path logic: resolve the `tools/` directory relative to `debug.getinfo(1).source` (the `tools.lua` file's location) so it works regardless of where lazy installs the plugin
- [x] 4.3 Emit `vim.notify` at WARN level for any tool file that cannot be found (not found check gates the symlink)
- [x] 4.4 Call `require("neph.tools").install()` from `M.setup()` in `init.lua`

## 5. Tests & Docs

- [x] 5.1 Add or update `tests/` unit tests: verify `config.defaults` has all expected keys including `multiplexer = nil`
- [x] 5.2 Update `README.md`: document the `multiplexer` option with examples for each value; note that tmux/zellij are stubs
- [x] 5.3 Update `README.md`: document that `setup()` auto-installs `shim` and `pi.ts` and describe what each tool does
- [x] 5.4 Smoke-test: install neph.nvim in a fresh lazy.nvim config, call `setup()`, confirm symlinks are created and agents launch correctly
