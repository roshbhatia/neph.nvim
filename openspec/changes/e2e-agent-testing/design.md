## Context

neph.nvim's existing tests are split across two levels:
- **Lua unit tests** (plenary/busted): test config, agents, context, history, placeholders, session — all without a live neovim
- **TypeScript unit tests** (vitest): test neph-cli commands, gate parsers, shared lib — all with mocked `spawn`

Neither level can catch:
- Runtime bundling failures (stale dist/ not matching source)
- Process lifecycle bugs (createNephQueue timing, extension loading)
- Symlink/merge correctness in tools.install()
- Agent launch failures that crash neovim

The pi crash bug was caused by a behavioral change in `createNephQueue` (await vs fire-and-forget) that no unit test could detect because they mock `spawn`.

## Goals / Non-Goals

**Goals:**
- Catch agent launch crashes (like the pi bug) automatically before they reach users
- Verify tools.install() creates correct symlinks and JSON merges
- Verify each installed agent opens in a headless neovim terminal without crashing
- Run e2e tests in CI alongside existing lint and unit tests
- Test agents in isolation — one agent per test, no cross-contamination

**Non-Goals:**
- Testing agent AI capabilities (we just verify they start without crashing)
- Interactive review flow testing (would require simulating user input in vimdiff)
- Testing all 10 agents — only test agents that are installable and have integrations
- Replacing existing unit tests — e2e complements, not replaces

## Decisions

### 1. Test runner: Lua script via `nvim --headless`

Use a Lua test script run via `nvim --headless -l tests/e2e/run.lua` rather than an external test framework.

**Why over plenary/busted**: Plenary busted tests are designed to NOT require a live neovim (per project constraints), but e2e tests explicitly need one. A standalone Lua script gives full control over the neovim lifecycle.

**Why over a Node.js harness**: The thing being tested IS neovim — running tests from inside neovim is the most natural and reliable approach. No RPC client needed.

**Alternatives considered:**
- neovim remote RPC from Node.js — adds complexity, another dependency, fragile connection management
- plenary busted with `vim.fn.jobstart` — awkward to assert on async terminal state

### 2. Agent installation: npm/pipx/cargo in CI, optional locally

Agents are installed as part of the CI pipeline setup, not as repo dev dependencies. Locally, e2e tests skip agents that aren't installed (graceful degradation).

**Why not repo dev dependencies**: Agent CLIs are large binaries (amp is Rust, pi is npm, claude is npm). Adding them to package.json would bloat install time and conflict with the plugin's zero-runtime-dep philosophy.

**CI installs**: The Dagger container already uses `nix develop` — agent binaries can be added to `shell.nix` or installed via npm/cargo in the CI script.

**Local behavior**: Tests check `vim.fn.executable(agent.cmd)` before running agent-specific tests. Missing agents are skipped with a warning, not failures.

### 3. Test tiers: smoke → launch → lifecycle

Three tiers, each building on the previous:

- **Smoke (always runs)**: `require("neph").setup()` succeeds, tools.install() creates expected symlinks/merges, agents.get_all() returns expected list
- **Launch (per-agent, skip if not installed)**: Open agent terminal via `session.open()`, wait for terminal buffer to exist, verify `vim.g.<agent>_active` is set, close terminal, verify cleanup
- **Lifecycle (extension agents only)**: Verify extension-based agents (pi, amp, opencode) load their extension code without errors — check that the bundled dist/ files are valid JavaScript

### 4. Timeout-based assertions for async terminal ops

Agent terminals are async — use `vim.wait()` with configurable timeout (default 10s) for assertions like "terminal buffer exists" and "vim.g set". Fail with descriptive message on timeout.

### 5. Isolated test runs

Each agent test runs in a fresh `nvim --headless` invocation. No shared state between agent tests. This prevents one crashing agent from poisoning the rest.

**Why not one nvim instance**: If pi crashes neovim (as it did), it would prevent all subsequent agent tests from running.

## Risks / Trade-offs

- **CI time increase** → Agent installs add ~2-5 min to CI. Mitigate by caching npm/cargo in the Dagger container layer.
- **Agent version drift** → Agents update independently and may break. Mitigate by pinning versions in CI and testing against stable releases only.
- **Flaky tests** → Terminal startup timing varies. Mitigate with generous timeouts and retry logic for known-flaky operations.
- **Agent auth requirements** → Some agents (claude, gemini, copilot) need API keys to fully start. Mitigate by testing only that they launch without crashing — don't test authenticated flows. Most agents show a prompt/error but don't crash.
- **PI_HOME / config contamination** → Agent configs may conflict. Mitigate by using isolated HOME dirs per test (XDG_CONFIG_HOME, etc.).
