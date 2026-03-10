## Why

The current tool installation system mutates user config files (JSON merges into `~/.claude/settings.json`, symlinks into `~/.local/bin/`) at plugin setup time. This is invasive — it touches files owned by other tools, requires an explicit `:NephTools install` step, and leaves artifacts behind if neph.nvim is removed. Since neph controls the agent terminal launch (command, args, env vars), we can pass integration config at runtime instead, eliminating the install step entirely for hook-based agents.

## What Changes

- **Claude agent launches with `--settings` flag** containing hook definitions as inline JSON, computed at launch time with absolute paths to neph-cli. No more merging into `~/.claude/settings.json`.
- **neph-cli symlink to `~/.local/bin/neph` eliminated** for agents launched through neph. Hook commands use absolute paths to `tools/neph-cli/dist/index.js` instead.
- **Agent definitions gain a `launch_args_fn`** (or equivalent) that can compute args dynamically at launch time, since absolute paths depend on `plugin_root()`.
- **The `tools.merges` manifest type becomes unnecessary** for Claude (and any future agents that support runtime settings flags). The merge infrastructure stays for agents that still need it (e.g., Cursor, until it gains equivalent support).
- **Extension agents (Pi, Amp, OpenCode) unchanged** — these require plugins loaded from agent-specific directories at agent startup. No runtime flag alternative exists for their plugin systems.
- **Build step remains** — neph-cli and extension agent TypeScript still needs `npm run build`. Only the install-into-user-dirs step is eliminated.

## Capabilities

### New Capabilities
- `runtime-agent-config`: Dynamic computation of agent launch arguments at terminal open time, enabling runtime injection of hooks/settings via CLI flags and absolute paths instead of persistent config file installation.

### Modified Capabilities
- `tool-install`: The universal neph-cli symlink becomes optional (only needed for out-of-neph usage). Claude's `tools.merges` is removed in favor of runtime `--settings`.
- `agent-tool-manifests`: Claude's manifest drops its `merges` entry. A new `launch_args` or `launch_args_fn` field is introduced on AgentDef for dynamic arg computation.

## Impact

- `lua/neph/agents/claude.lua` — removes `tools.merges`, adds dynamic args
- `lua/neph/internal/session.lua` — resolves dynamic args at launch time
- `lua/neph/backends/snacks.lua` — passes resolved args (minor)
- `lua/neph/tools.lua` — neph-cli symlink becomes optional/skippable
- `tools/claude/settings.json` — may become unused (kept for manual install reference)
- `lua/neph/config.lua` — AgentDef type gains optional `launch_args_fn` field
- Tests: contract tests, agent definition tests, session launch tests
