## 1. Extract Lua Scripts

- [x] 1.1 Create `tools/core/lua/` directory
- [x] 1.2 Extract `LUA_OPEN` string literal from `shim.py` into `tools/core/lua/open.lua` (strip the enclosing `r"""..."""` and leading/trailing blank lines)
- [x] 1.3 Extract `LUA_REVERT` string literal from `shim.py` into `tools/core/lua/revert.lua`
- [x] 1.4 Extract `LUA_PREVIEW` string literal from `shim.py` into `tools/core/lua/preview.lua`

## 2. Update shim.py to Load from Files

- [x] 2.1 Add `_LUA_DIR = Path(__file__).parent / "lua"` near the top of `shim.py` (after existing imports/constants)
- [x] 2.2 Replace the three `LUA_*` raw-string literals with file reads: `LUA_OPEN = (_LUA_DIR / "open.lua").read_text()`, and same for `revert` and `preview`
- [x] 2.3 Verify the module still imports cleanly and `shim status` works end-to-end

## 3. Tests — Script Loading

- [x] 3.1 In `tools/core/tests/test_shim.py`, add `TestLuaScriptLoading` class with a test that asserts each `LUA_*` constant is a non-empty string after import
- [x] 3.2 Add a test asserting that removing/renaming `open.lua` and re-importing `shim` raises `FileNotFoundError` (use `monkeypatch` to swap `_LUA_DIR`)

## 4. Tests — Script Behavior via FakeNvimServer

- [x] 4.1 Add test: assert that the `nvim_exec_lua` call for `cmd_open` has `params[0]` equal to `LUA_OPEN`
- [x] 4.2 Add test: assert that the `nvim_exec_lua` call for `cmd_revert` has `params[0]` equal to `LUA_REVERT`
- [x] 4.3 Add test: assert that the `nvim_exec_lua` call for `cmd_preview` has `params[0]` equal to `LUA_PREVIEW`

## 5. README Update

- [x] 5.1 In the Companion Tools table, update the `shim.py` row to note that Lua scripts live in `tools/core/lua/`

## 6. Verify

- [x] 6.1 Run `task tools:test` from repo root and confirm all tests pass (Python + TypeScript)
- [x] 6.2 Run `shim status` inside Neovim terminal to confirm the extracted scripts load and connect correctly
