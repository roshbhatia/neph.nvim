## Context

`shim.py` currently implements its own msgpack-rpc transport: it opens a raw
Unix socket, hand-rolls `[type, msgid, method, params]` frames via `msgpack.packb`,
and manually sequences request IDs and reads response frames in a loop. This is
exactly what pynvim already does — correctly, with years of battle-testing,
proper notification handling, and a clean Python API.

The existing test suite has to spin up a `FakeNvimServer` (a real Unix socket
server that speaks msgpack-rpc) just to verify basic framing. With pynvim, the
`Nvim` object is trivially mockable: every call goes through `nvim.exec_lua()`
which is a single method on a concrete object.

## Goals / Non-Goals

**Goals**
- Replace hand-rolled `NvimRPC` class with `pynvim.attach("socket", path=...)`
- Remove `msgpack` as a direct dependency (pynvim bundles its own transport)
- Rewrite test suite to use `unittest.mock.patch("pynvim.attach")` — no real
  socket server required for the majority of tests
- Add a headless-nvim integration test fixture for the handful of tests that
  genuinely benefit from a real Neovim process
- Achieve ≥90% branch coverage on all `cmd_*` functions

**Non-Goals**
- Change the Click CLI surface (commands, arguments, or help text)
- Change any Lua scripts under `tools/core/lua/`
- Change `pi.ts` or any TypeScript code
- Change the public Lua plugin API

## Decisions

### D1: pynvim.attach as the sole transport

**Decision**: Use `pynvim.attach("socket", path=SOCKET_PATH)` and call
`nvim.exec_lua(script, args)` directly.

**Rationale**: pynvim is the official Python client for Neovim's msgpack-rpc
protocol. It handles framing, msgid sequencing, async notifications, and
reconnection. It is also what Neovim's own CI uses to test the RPC interface.

**Alternatives considered**:
- Keep hand-rolled NvimRPC — rejected: duplicates pynvim; hard to test; already caused bugs
- Use neovim-client (rust) via subprocess — rejected: wrong language, adds complexity

### D2: Timeout via socket.setdefaulttimeout, not pynvim API

**Decision**: Set `socket.setdefaulttimeout(timeout)` before calling
`pynvim.attach`, then reset it to `None` afterwards for `cmd_preview`.

**Rationale**: pynvim does not expose a per-connection timeout parameter.
`socket.setdefaulttimeout` is a Python stdlib call that applies globally to all
new sockets created in the current thread; since shim is single-threaded and
one-shot, this is safe. `cmd_preview` requires no timeout (blocks on user input).

**Alternatives considered**:
- Monkey-patch pynvim internals — rejected: brittle, breaks on pynvim upgrades
- Add a `threading.Timer` to kill the process — rejected: adds complexity; the
  SIGTERM logic in pi.ts already handles runaway shim processes at the outer level

### D3: Mock pynvim.attach in unit tests; headless nvim for integration tests

**Decision**: The primary test layer uses `unittest.mock.patch("pynvim.attach")`
returning a `MagicMock`. A secondary `@pytest.mark.integration` layer spins up
`nvim --headless --listen /tmp/test.sock` as a subprocess fixture for tests
that verify actual Lua execution.

**Rationale**: Mocking `pynvim.attach` is trivially easy and covers all logic
paths in `cmd_*` functions. Integration tests are valuable for the Lua scripts
themselves but slow; keeping them separate lets CI run unit tests fast and opt
into integration tests with `-m integration`.

**Alternatives considered**:
- Keep FakeNvimServer — rejected: it re-implements pynvim's job; fragile
- Only headless nvim tests — rejected: slow, requires Neovim installed in test env

### D4: pynvim replaces msgpack in pyproject.toml

**Decision**: Remove `msgpack>=1.0` from `dependencies` and `dev` groups;
add `pynvim>=0.5`.

**Rationale**: pynvim vendors its own msgpack transport internally; adding
`msgpack` separately causes version conflicts and is redundant.

**Alternatives considered**:
- Keep msgpack as dev dep for tests — rejected: tests no longer use it directly

### D5: connect() becomes get_nvim(), returns pynvim.Nvim

**Decision**: Rename `connect()` → `get_nvim(timeout)` returning a
`pynvim.Nvim` object. All `cmd_*` functions call `get_nvim()` (or
`get_nvim(timeout=None)` for preview).

**Rationale**: Naming `get_nvim` is explicit about what it returns and aligns
with pynvim's own documentation terminology.

## Risks / Trade-offs

- **pynvim install size**: pynvim pulls in more transitive deps than bare msgpack.
  Mitigated: uv resolves deps lazily; shim.py is a uv inline script so deps are
  cached per-version and don't affect the Neovim plugin install.
- **pynvim version skew**: pynvim's API is stable since 0.4; we pin `>=0.5`.
  Mitigated: uv lockfile pins the exact version used in development.
- **socket.setdefaulttimeout is process-global**: Safe here because shim is
  single-threaded and one-shot. Would be a problem in a long-lived server.

## Migration Plan

1. Update `pyproject.toml`: swap `msgpack` for `pynvim`
2. Rewrite `shim.py`: remove `NvimRPC`, replace `connect()` with `get_nvim()`,
   update all `cmd_*` to use pynvim API
3. Rewrite `conftest.py`: remove `FakeNvimServer`; add `mock_nvim` fixture and
   optional headless nvim fixture
4. Rewrite `test_shim.py`: all tests use mock or headless fixture
5. Run `uv sync` and `uv run pytest` to verify
6. Run `task lint` to verify flake8 clean

Rollback: `git revert` — no database migrations, no external state.

## Open Questions

- Should the headless nvim integration tests run in CI by default, or only on
  demand? (Proposal: off by default; enabled via `NEPH_INTEGRATION_TESTS=1`)
