## Context

`neph.nvim` has accumulated a few naming and API rough edges that need cleaning up:

1. **`"native"` label** — the snacks.nvim backend is called `"native"` in user-facing config, which is confusing because `snacks.nvim` is actually a named dependency, not a generic fallback. The internal module stays `native.lua` (a refactor is out of scope) but the user-facing config value changes to `"snacks"`.

2. **Auto-detect default** — `multiplexer = nil` triggers env-var heuristics (SSH_CONNECTION → native, WEZTERM_PANE → wezterm). This adds complexity for a feature (WezTerm) that few users need. The default should just be `"snacks"` — it always works, it's the only dep, and users with WezTerm can opt in explicitly.

3. **`file_refresh` over-exposure** — `timer_interval` and `updatetime` are internal timer knobs that aren't user-relevant. They'll stay hardcoded inside `file_refresh.lua`; only `enable` stays in the public API.

4. **Preview/diff broken** — `LUA_PREVIEW` uses `vim.fn.getcharstr()` inside `nvim_exec_lua`, called from an agent terminal that itself lives inside the same Neovim instance. The Lua references `ESC` as an uninitialized local (evaluates to `nil`), so ESC-to-reject never fires. Additionally, after recent refactoring the socket forwarding (how `NVIM_SOCKET_PATH` gets into the terminal env) may have drifted. The fix requires: (a) defining `local ESC = '\27'`, and (b) confirming the native backend still injects `NVIM_SOCKET_PATH` into the terminal environment.

5. **README drift** — mentions the deleted `nvim-shim` bash wrapper, uses `multiplexer = nil`, and doesn't explain the socket mechanism.

## Goals / Non-Goals

**Goals:**
- Rename `"native"` config value → `"snacks"`, update all call sites
- Make `multiplexer = "snacks"` the default; remove auto-detect heuristics from `detect_backend()`
- Remove `timer_interval` and `updatetime` from the public `neph.FileRefreshConfig` type; hardcode them in `file_refresh.lua`
- Fix `LUA_PREVIEW`: define `ESC`, verify `getcharstr` / `input` contract, confirm `NVIM_SOCKET_PATH` injection
- README: remove nvim-shim row, update multiplexer docs, add socket section
- Update tests to reflect new `multiplexer = "snacks"` default and simplified `file_refresh` type

**Non-Goals:**
- Rename `lua/neph/internal/backends/native.lua` (internal filename; out of scope)
- Full WezTerm or tmux backend implementation
- Changing the auto-symlink behaviour for `shim.py` / `pi.ts`
- Rewriting the preview UI to use floating windows or `vim.ui.select` (can be a follow-up)

## Decisions

### D1: Map `"snacks"` config value → `native.lua` backend internally

`session.lua`'s `detect_backend()` returns `"snacks"` (via config default). The backend selection block maps it:

```lua
if btype == "wezterm" then ...
elseif btype == "tmux" then ...
elseif btype == "zellij" then ...
else  -- "snacks" and any unknown value
  backend = require("neph.internal.backends.native")
end
```

No rename of the backend file. Old code that passed `multiplexer = "native"` will silently fall through to the `else` branch (native backend) — acceptable degradation.

**Alternative considered:** Add an `elseif btype == "snacks"` arm explicitly.  
**Rejected:** The `else` fallback is equally correct and avoids a dangling `"native"` arm.

### D2: Remove auto-detect entirely — `detect_backend()` becomes a one-liner

With `multiplexer` always set (default `"snacks"` or explicit), `detect_backend()` simplifies to:

```lua
local function detect_backend()
  return config.multiplexer or "snacks"
end
```

The SSH and WEZTERM_PANE env-var checks are deleted. Users who relied on auto-wezterm must now set `multiplexer = "wezterm"` explicitly — documented as a minor breaking change.

**Alternative considered:** Keep auto-detect as a fallback when `multiplexer = nil`.  
**Rejected:** The complexity cost outweighs the convenience; the old nil default is being removed anyway.

### D3: Fix `LUA_PREVIEW` minimally — define `ESC`, no architecture change

The root bug is `ESC` used without being defined (Lua returns `nil` for undefined locals; `ch == nil` never matches a string from `getcharstr`). Fix: add `local ESC = '\27'` near the top of `LUA_PREVIEW`.

`vim.fn.getcharstr()` inside `nvim_exec_lua` does work for interactive use (it suspends the RPC response and processes UI events). The blocking model is sound; the bug is purely the missing constant.

Additionally, verify that `native.lua`'s `M.open()` still injects `NVIM_SOCKET_PATH` into the terminal env — if that was dropped during refactoring, the shim would connect to the wrong socket or none at all.

**Alternative considered:** Rewrite hunk review as a floating window with `vim.keymap.set` callbacks.  
**Deferred:** Higher complexity, would require async RPC (the current sync model is simpler). Can be a follow-up.

### D4: `file_refresh.lua` hardcodes timer values

`file_refresh.lua` will use `opts.timer_interval or 1000` and `opts.updatetime or 750` internally, accepting them if present (backward compat) but not exposing them in the public type. `neph.FileRefreshConfig` becomes `{ enable?: boolean }` only.

## Risks / Trade-offs

- **[Risk] `multiplexer = "native"` from existing user configs silently falls to snacks** → Mitigation: this is correct behaviour; add a note in the README changelog section.
- **[Risk] Auto-wezterm users lose auto-detection** → Mitigation: document in README, provide one-line migration (`multiplexer = "wezterm"`).
- **[Risk] ESC fix alone may not restore full preview functionality** → Mitigation: test with `shim preview <file>` in an actual nvim terminal after the fix; if `getcharstr` still misbehaves, escalate to a follow-up float-window approach.

## Migration Plan

1. Update `config.lua` — rename `"native"` references, simplify `FileRefreshConfig`
2. Update `session.lua` — simplify `detect_backend()`; map `"snacks"` in backend selection
3. Update `file_refresh.lua` — hardcode timer values
4. Patch `shim.py` `LUA_PREVIEW` — add `ESC` constant; audit `NVIM_SOCKET_PATH` injection in `native.lua`
5. Update `README.md`
6. Update `tests/` — assert `multiplexer = "snacks"`, simplified `file_refresh`

No database migrations, no breaking API changes in `neph.api`. The only breaking change is `multiplexer = "native"` → `"snacks"` (value rename) and `multiplexer = nil` no longer auto-detects.

## Open Questions

- Does `vim.fn.getcharstr()` reliably suspend an `nvim_exec_lua` call across all Neovim ≥ 0.10 versions, or is there a version regression? (Unblock by manual testing after the ESC fix.)
