## Context

`neph.nvim` currently ships only Lua modules. The companion tooling that makes it truly useful — `nvim-shim` (bash RPC bridge), `shim.py` (Python msgpack-rpc client), and `pi.ts` (pi coding-agent TypeScript extension) — live in the user's personal dotfiles (`~/.config/nvim/tools/` and `~/.local/bin/`). A `lazy.nvim`-driven `after/plugin/ai-shim.lua` autocmd handled symlinking, but that file is part of sysinit.nvim, not neph.nvim.

Additionally, `init.lua` directly embeds the `defaults` table and all type annotations. `session.lua` auto-detects the multiplexer backend (SSH → native, WEZTERM_PANE → wezterm, fallback → native) with no escape hatch for users who want to force a specific backend.

## Goals / Non-Goals

**Goals:**
- Bundle `tools/nvim-shim`, `tools/shim.py`, and `tools/pi.ts` directly in the neph.nvim repo.
- Have `M.setup()` auto-symlink the tools to their canonical locations so installing neph.nvim via lazy.nvim is sufficient.
- Extract the `defaults` table and `neph.Config` type annotations into `lua/neph/config.lua`.
- Add an explicit `multiplexer` config key (`"native"` | `"wezterm"` | `"tmux"` | `"zellij"` | `nil`).
- Scaffold stub backends for `tmux` and `zellij` that satisfy the backend interface.

**Non-Goals:**
- Implementing full tmux or zellij pane management (stubs only).
- Changing how existing `wezterm` or `native` backends behave.
- Modifying the sysinit.nvim AI plugin consolidation (tracked as a separate follow-up).
- Package-manager integration (Nix, Homebrew) for the tools — symlinking is sufficient.

## Decisions

### D1: Bundle tools as plain files, not as a sub-package

The tools are already self-contained scripts. Keeping them as checked-in files under `tools/` is simpler than a git submodule or external download. Symlinks mean edits to the repo immediately take effect, matching the existing pattern in sysinit.nvim's `ai-shim.lua`.

**Alternatives considered:**
- *Download at install time*: Requires network access and a bootstrap script; too complex for a Neovim plugin.
- *Nix derivation*: Appropriate for sysinit.nvim but out of scope here.

### D2: Symlink at `M.setup()` time, not via a VimEnter autocmd

Symlinking inside `setup()` is synchronous and predictable. The `ai-shim.lua` approach (VimEnter autocmd) worked but added a frame of latency and was a separate file that users had to know about. Running it eagerly in `setup()` is explicit and testable.

The symlink target directories are created if they don't exist (`vim.fn.mkdir(..., "p")`). The source is `vim.fn.stdpath("data") .. "/lazy/neph.nvim/tools/<file>"` — the standard lazy.nvim install path.

**Alternatives considered:**
- *BufEnter autocmd*: Too frequent; `setup()` once is correct.

### D3: `multiplexer` key overrides auto-detection; `nil` keeps existing behavior

Adding `multiplexer = nil` as the default preserves full backward compatibility. When the value is a string, `detect_backend()` returns it directly without inspecting environment variables. This means users in WezTerm who want to force native just set `multiplexer = "native"`.

`tmux` and `zellij` are accepted values today but map to stub backends that log a `vim.notify` warning and fall back to native, so the config key is valid but not yet functional — giving a clear upgrade path.

**Alternatives considered:**
- *Separate `backend` key*: Naming ambiguity with the internal `backend` variable; `multiplexer` better describes the concept.
- *Remove auto-detection entirely*: Would be a breaking change for existing users.

### D4: `lua/neph/config.lua` as the single source of truth for defaults

A dedicated module follows the common Neovim plugin pattern (e.g., `snacks.nvim`, `blink.cmp`) and makes defaults testable in isolation. `init.lua` requires `config.lua` and calls `config.with(opts)` (or `vim.tbl_deep_extend`) to produce the merged config.

## Risks / Trade-offs

- **Lazy install path assumption**: Symlinking from `vim.fn.stdpath("data") .. "/lazy/neph.nvim/tools/"` assumes lazy.nvim. Users with a different plugin manager will see a silent no-op (file not readable check gates the symlink call). → Mitigation: emit `vim.notify` at WARN level when the source file isn't found.
- **Stub backends accept the key silently then fall back**: A user who sets `multiplexer = "tmux"` gets native behavior without an error. → Mitigation: stubs emit a `vim.notify` WARN once on setup so the user knows.
- **Existing symlinks outside neph**: The old `~/.config/nvim/tools/shim.py` and `after/plugin/ai-shim.lua` in sysinit.nvim will still run if the user hasn't cleaned them up. → Mitigation: `ln -sf` overwrites whatever is there; document in README.

## Migration Plan

1. Copy `nvim-shim`, `shim.py`, `pi.ts` into `tools/` and commit.
2. Create `lua/neph/config.lua` with defaults and types; update `init.lua` to require it.
3. Update `session.lua` to read `config.multiplexer`; add `tmux.lua` and `zellij.lua` stubs.
4. Add symlink logic to `M.setup()`.
5. Users already on neph.nvim: existing behavior is unchanged (all new keys default to `nil` / previous behavior).
6. Users who were relying on sysinit.nvim's `ai-shim.lua`: remove that file; neph now handles it.
