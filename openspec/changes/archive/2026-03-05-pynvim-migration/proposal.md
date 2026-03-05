## Why

`shim.py` hand-rolls msgpack-rpc framing over a raw Unix socket — a fragile
low-level protocol implementation that duplicates what pynvim already provides
correctly, with connection management, error handling, and a stable Python API.
The existing hand-rolled approach is hard to unit-test (tests must spin up a
real or fake msgpack socket server) and has already caused correctness bugs
(duplicate frames, timeout races). Migrating to pynvim removes ~60 lines of
transport code, gives us a well-tested RPC layer for free, and enables much
richer pytest coverage using pynvim's own test utilities.

## What Changes

- **Replace `NvimRPC` class** with `pynvim.attach("socket", path=...)` — pynvim
  handles framing, msgid sequencing, notification filtering, and reconnects.
- **Replace `connect()` helper** with a thin `get_nvim()` factory that attaches
  via pynvim and returns a `pynvim.Nvim` instance.
- **All `cmd_*` functions** updated to call `nvim.exec_lua(script, args)` via
  pynvim rather than the hand-rolled `NvimRPC.exec_lua`.
- **`cmd_preview` timeout** — pynvim does not apply a socket timeout by default
  (blocking, correct for interactive preview); all other commands keep the
  existing 30 s default via `socket.setdefaulttimeout` before attaching.
- **Test suite rewritten** using `pynvim`'s `conftest` patterns and `pytest`
  fixtures; fake-server conftest replaced with either a real embedded nvim
  subprocess (headless) or `unittest.mock.patch` on `pynvim.attach`.
- **`pyproject.toml`**: replace `msgpack>=1.0` runtime dep with `pynvim>=0.5`.
- **No changes** to the Click CLI surface, Lua scripts, pi.ts, or public API.

## Capabilities

### New Capabilities

- `pynvim-client`: pynvim-based Neovim RPC client replacing hand-rolled msgpack
- `shim-test-coverage`: comprehensive pytest suite covering all commands,
  timeout behaviour, error paths, and CLI dispatch with no real socket server

### Modified Capabilities

- `socket-integration`: requirements change — timeout is now set via
  `socket.setdefaulttimeout` before `pynvim.attach` rather than on a raw sock;
  preview command still has no timeout; error messages stay compatible.

## Impact

- `tools/core/shim.py`: NvimRPC class and connect() removed; pynvim attach used instead
- `tools/core/pyproject.toml`: `msgpack>=1.0` → `pynvim>=0.5` (runtime + dev deps)
- `tools/core/tests/conftest.py`: FakeNvimServer replaced with pynvim-compatible fixtures
- `tools/core/tests/test_shim.py`: rewritten for pynvim API; all existing scenarios retained
- No changes to public Lua API, pi.ts, or CI pipeline
