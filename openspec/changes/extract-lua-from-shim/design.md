## Context

`shim.py` contains three Lua scripts as inline Python raw strings:

| Constant | Size | Purpose |
|----------|------|---------|
| `LUA_OPEN` | ~14 lines | Opens file in agent tab via `tabnew`/`edit` |
| `LUA_REVERT` | ~20 lines | Closes diff windows, restores pre-preview state |
| `LUA_PREVIEW` | ~187 lines | Full hunk-by-hunk vimdiff review loop |

Because these are embedded strings, editors provide no Lua syntax highlighting or linting, they cannot be tested in isolation, and diffs touching the preview logic are noisy.

## Goals / Non-Goals

**Goals:**
- Move each Lua block to `tools/core/lua/{open,revert,preview}.lua`
- Load them at `shim.py` module level; no change to call sites
- Add isolated pytest tests for each Lua script's RPC behavior

**Non-Goals:**
- Changing any Lua logic (pure extraction — behavior must be identical)
- Modularising the Lua itself (no `require`, no shared helpers)
- Lua test runner integration (tests remain in pytest via `FakeNvimServer`)

## Decisions

### D1 — Load with `Path(__file__).parent / "lua" / "<name>.lua"`

```python
_LUA_DIR = Path(__file__).parent / "lua"
LUA_OPEN    = (_LUA_DIR / "open.lua").read_text()
LUA_REVERT  = (_LUA_DIR / "revert.lua").read_text()
LUA_PREVIEW = (_LUA_DIR / "preview.lua").read_text()
```

`shim.py` is always run as a file on disk via `uv --script`, never zipped, so `Path(__file__).parent` is reliable and simpler than `importlib.resources`.

### D2 — No `pyproject.toml` packaging changes needed

`uv run --script` runs `shim.py` directly. The `lua/` files just need to be siblings to `shim.py` on the filesystem (`tools/core/lua/`). No install step, no package data config.

### D3 — Test strategy: assert `nvim_exec_lua` params match file contents

Each behavior test will:
1. Spin up `FakeNvimServer` (existing fixture)
2. Call the relevant `cmd_*` function
3. Assert the `params[0]` of the captured RPC request equals the loaded script content

This guarantees the correct file is being sent to Neovim without needing a live editor.

## Risks / Trade-offs

- **`shim.py` fails if `lua/` dir missing** → `read_text()` raises `FileNotFoundError` naturally; the path in the error message is self-documenting
- **Python module reload in tests** → Lua paths are module-level constants; `importlib.reload(shim)` after patching `_LUA_DIR` is sufficient for missing-file tests
