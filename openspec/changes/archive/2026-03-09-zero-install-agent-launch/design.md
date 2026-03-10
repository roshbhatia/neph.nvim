## Context

Currently, neph.nvim installs agent integrations by mutating files in the user's home directory:
- **Claude**: merges hook entries into `~/.claude/settings.json`
- **Cursor**: symlinks `hooks.json` to `~/.cursor/hooks.json`
- **neph-cli**: symlinks `dist/index.js` to `~/.local/bin/neph`
- **Extension agents** (Pi, Amp, OpenCode): symlink plugins into agent-specific dirs

This happens at plugin setup time via `tools.install_async()`. The problem: it's invasive, requires a manual `:NephTools install` step, and leaves artifacts if the plugin is removed.

Key discovery: Claude CLI supports `--settings <json>` which **additively merges** settings from all sources (userSettings, projectSettings, flagSettings, etc.). Hooks from `--settings` are collected alongside the user's own hooks — no replacement, no conflict.

Since neph controls the terminal launch (command, args, env vars via `session.lua` → `backend.open()`), we can inject config at launch time instead.

## Goals / Non-Goals

**Goals:**
- Eliminate `~/.claude/settings.json` mutation for Claude agent
- Eliminate `~/.local/bin/neph` symlink requirement for neph-launched agents
- Introduce a mechanism for agents to compute launch args dynamically (needs `plugin_root()`)
- Keep backward compatibility — existing `tools.merges` infrastructure stays for agents that need it

**Non-Goals:**
- Eliminating symlinks for extension agents (Pi, Amp, OpenCode) — their plugin systems require files at fixed paths
- Eliminating the neph-cli build step — TypeScript still needs compilation
- Supporting Cursor runtime config — Cursor CLI doesn't read `hooks.json` and has no `--settings` equivalent yet
- Removing the `tools.lua` install system — it's still needed for extension agents and optional manual install

## Decisions

### 1. Add `launch_args_fn` to AgentDef

**Decision**: Add an optional `launch_args_fn(root: string) -> string[]` function field to `AgentDef` that computes additional args at launch time.

**Why not just hardcode args?** The hook command needs an absolute path to `neph-cli/dist/index.js`, which depends on `plugin_root()` — a runtime value. Static `args` can't express this.

**Alternative considered**: Compute the full `args` array as a function replacing the static `args` field. Rejected because most agents have simple static args, and this would add unnecessary complexity to the common case.

**How it works**: `session.lua:open()` calls `launch_args_fn(plugin_root)` and appends the result to `agent.args` when building `full_cmd`.

### 2. Claude uses `--settings` with inline JSON

**Decision**: Claude's agent definition drops `tools.merges` and instead uses `launch_args_fn` to return `{"--settings", json_string}` containing the hook definition with an absolute path to neph-cli.

**Generated command**:
```
claude --permission-mode plan --settings '{"hooks":{"PreToolUse":[{"matcher":"Edit|Write","hooks":[{"type":"command","command":"node /path/to/neph.nvim/tools/neph-cli/dist/index.js gate --agent claude"}]}]}}'
```

**Why `node <absolute-path>` instead of just the absolute path?** Using `node` explicitly avoids dependence on the shebang being interpreted correctly and file execute permissions being set. More robust across environments.

**Alternative considered**: Using `--settings /path/to/neph.nvim/tools/claude/settings.json` (file path instead of inline JSON). Rejected because the settings file contains `"neph gate"` which assumes the symlink exists. We'd need a separate generated file, adding complexity.

### 3. neph-cli symlink becomes optional

**Decision**: The `~/.local/bin/neph` symlink is no longer required for agents launched through neph. The `install_universal()` function still creates it, but only when explicitly requested via `:NephTools install all`. The automatic install at setup time skips the symlink.

**Rationale**: Hook commands now embed absolute paths. The symlink is only useful if the user wants to call `neph` from their own shell outside of neph.nvim.

### 4. Session.lua resolves dynamic args at open time

**Decision**: `session.lua:open()` is the resolution point. It already builds `agent_config` from the agent definition. It will additionally call `launch_args_fn` if present and append the results to args before constructing `full_cmd`.

**Why session.lua and not the backend?** The backend receives a ready-to-execute `agent_config`. Keeping arg resolution in session.lua maintains the backend's role as a pure executor.

## Risks / Trade-offs

**[Risk: Claude `--settings` JSON shell escaping]** → The inline JSON contains quotes and special characters. Mitigation: `session.lua` passes args as a table to `Snacks.terminal.open()`, which handles escaping. For WezTerm backend, args are shell-escaped via `%q` format.

**[Risk: Claude changes `--settings` behavior in future versions]** → We depend on additive merge behavior verified by reading Claude's source code. Mitigation: Test in CI that verifies `--settings` flag presence in Claude CLI help output. Add a comment in `claude.lua` noting the dependency.

**[Risk: Build step still required]** → Users still need `npm run build` for neph-cli before first use. Mitigation: The build runs automatically at setup time (unchanged). Only the symlink step changes.

**[Trade-off: Longer command line]** → The `--settings` JSON makes the launch command verbose. Acceptable — it's not user-visible (launched programmatically in a terminal buffer).

**[Trade-off: Extension agents unchanged]** → Pi/Amp/OpenCode still need symlink installation. This is a fundamental limitation of their plugin architectures — they load plugins from fixed directories at startup with no runtime override.
