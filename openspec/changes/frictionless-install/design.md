# Design: Frictionless Install

## Core Decision: print-settings + global install

Two new surfaces. Both are additive — no existing code removed.

### `neph print-settings <agent>`

Reads `tools/<agent>/settings.json` (the bundled template) from the same
`TOOLS_ROOT` already used by `applyIntegration`. Writes the file contents to
stdout as a minified JSON string (no newlines). No files touched.

Used in shell aliases:

```bash
alias claude='claude --settings "$(neph print-settings claude)"'
```

Claude Code's `--settings` flag accepts either a file path or a raw JSON
string. Passing the template JSON directly means zero files written anywhere.

### `neph install` / `neph uninstall`

Writes (or removes) neph hook config in each agent's **global** config
directory. This is the same merge/unmerge logic used by toggle today, just
targeting different paths.

```
Agent   Config path written by install
─────   ────────────────────────────────────────────
claude  (nothing written — use print-settings alias)
gemini  ~/.gemini/settings.json
cursor  ~/.cursor/hooks.json
codex   ~/.codex/hooks.json
```

Claude is intentionally omitted from the file-write path: the inline
`--settings` alias is cleaner and leaves no global state to clean up.

After writing, `neph install` prints the shell alias lines the user needs to
add to their shell config (`.zshrc`, `.bashrc`, etc.).

### Binary Path Detection

The PATH prefix workaround (`PATH=$HOME/.local/bin:$PATH neph ...`) exists
because `/bin/sh` doesn't source the user's shell profile. When `neph install`
writes hook commands, it uses the absolute path of the neph binary instead:

```typescript
function detectNephBin(): string {
  // Prefer explicit env override for testing
  if (process.env.NEPH_BIN) return process.env.NEPH_BIN;
  // Use the path of the currently-running process
  return process.execPath === process.argv[0]
    ? process.argv[1]           // node /path/to/neph/index.js
    : process.execPath;         // compiled binary
}
```

The absolute path is stable as long as the neph installation doesn't move.
On neph update (e.g. `home-manager switch`), the user re-runs `neph install`
to update the embedded paths. `neph install` is idempotent (merge semantics).

For `print-settings`, the command string is NOT embedded in the output — the
alias calls `neph print-settings` directly, which means the currently-running
neph is always used. No path baking needed for Claude.

### Template Command Strings

The template files (`tools/*/settings.json`, `tools/*/hooks.json`) currently
embed:

```json
"command": "PATH=$HOME/.local/bin:$PATH neph integration hook claude"
```

This is unchanged. The PATH prefix is the right default for per-project toggle
(where neph may only be in `~/.local/bin`). `neph install` replaces this with
the detected absolute path when writing to global config. `print-settings`
outputs the template as-is, relying on Claude's `--settings` flag being invoked
via an alias where the shell already knows about neph.

### Global Write Safety

`neph install` uses the same `mergeHooks` / `mergeCopilot` logic as toggle.
Existing entries in the user's global config files are preserved. Running
`neph install` twice is safe. `neph uninstall` uses `unmergeHooks` to remove
only neph-owned entries.

The only risk is `~/.gemini/settings.json` and Gemini bug #23138 (theme changes
wipe the file). `neph install` warns about this after writing gemini config:

```
gemini: warning — Gemini bug #23138: theme changes may overwrite
~/.gemini/settings.json. Re-run 'neph install gemini' after any theme change.
```

### Output Contract

`neph install` (stdout):

```
claude: skip (use alias below)
gemini: installed → ~/.gemini/settings.json
cursor: installed → ~/.cursor/hooks.json
codex:  installed → ~/.codex/hooks.json

Add to your shell config (~/.zshrc or ~/.bashrc):

  alias claude='claude --settings "$(neph print-settings claude)"'
  alias codex='codex --enable codex_hooks'
```

`neph install <agent>` installs only the named agent.

`neph uninstall` (stdout):

```
gemini: removed → ~/.gemini/settings.json
cursor: removed → ~/.cursor/hooks.json
codex:  removed → ~/.codex/hooks.json
claude: nothing to remove (no files written)
```

### Relationship to Existing Toggle

`neph integration toggle` continues to work exactly as today. It targets
project-local paths. It's the right tool for:
- CI environments that want explicit per-repo opt-in
- Repos committed to a team that wants neph enforced project-wide
- Testing / development of neph itself

`neph install` is the right tool for personal developer machines.

## File Map

```
tools/neph-cli/src/
  integration.ts     (modify) — add runInstallCommand, runPrintSettingsCommand,
                                detectNephBin; add global config paths to
                                Integration interface
  index.ts           (modify) — wire 'install', 'uninstall', 'print-settings'
                                subcommands

No template files changed.
No test files removed.
```

## Integration Definition Extension

The `Integration` interface gains an optional `globalConfigPath`:

```typescript
interface Integration {
  name: string;
  label: string;
  configPath: () => string;          // project-local (existing)
  globalConfigPath?: () => string;   // user-global (new, optional)
  templatePath: string;
  kind: "hooks" | "copilot" | "cupcake";
  requiresCupcake?: boolean;
}
```

`globalConfigPath` is absent for `claude` (no file written) and `opencode`
(cupcake model). Present for `gemini`, `cursor`, `codex`.

`neph install` uses `globalConfigPath`; toggle continues to use `configPath`.
