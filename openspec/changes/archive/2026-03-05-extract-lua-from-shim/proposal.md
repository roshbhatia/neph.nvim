## Why

`shim.py` currently embeds ~220 lines of Lua as raw Python string literals (`LUA_OPEN`, `LUA_REVERT`, `LUA_PREVIEW`). This makes the Lua invisible to editors (no syntax highlighting, no linting), impossible to unit-test in isolation, and hard to reason about when debugging the preview flow.

## What Changes

- Extract `LUA_OPEN`, `LUA_REVERT`, and `LUA_PREVIEW` from `shim.py` into standalone files under `tools/core/lua/`
- `shim.py` loads each script at startup using `Path(__file__).parent / "lua" / ...` — zero change to calling code
- Add pytest tests that verify each script is loaded and that each `cmd_*` function sends the correct script content to Neovim
- The `tools/core/lua/` directory sits alongside `shim.py` on disk; no packaging changes needed

## Capabilities

### New Capabilities
- `lua-scripts`: Standalone Lua script files for shim RPC operations (`open.lua`, `revert.lua`, `preview.lua`), loaded at runtime by `shim.py`

### Modified Capabilities
- `socket-integration`: Lua script loading is now file-based rather than inline string; README should note `tools/core/lua/` as the location of shim's Lua scripts

## Impact

- `tools/core/shim.py`: remove three inline `r"""..."""` blocks; add file-loading at module level
- `tools/core/lua/open.lua`, `revert.lua`, `preview.lua`: new files containing the extracted Lua
- `tools/core/tests/test_shim.py`: new tests asserting script loading and correct `nvim_exec_lua` params
- No changes to public CLI interface or RPC protocol
