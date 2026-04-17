# Spec: neph install / neph uninstall

## Commands

```
neph install [<agent>]      Install hooks globally for all agents, or one agent
neph uninstall [<agent>]    Remove hooks from all global agent configs, or one
```

## Global Config Paths

| Agent  | Global config path              | Action on install          |
|--------|---------------------------------|----------------------------|
| claude | (none)                          | Skip, print alias          |
| gemini | `~/.gemini/settings.json`       | mergeHooks                 |
| cursor | `~/.cursor/hooks.json`          | mergeHooks                 |
| codex  | `~/.codex/hooks.json`           | mergeHooks                 |

`~` is resolved from `process.env.HOME`. If `HOME` is not set, exit 1 with
`neph install: $HOME is not set`.

## Binary Path Substitution

Before merging, `neph install` rewrites the `command` field in every hook entry
it writes, replacing the template command with one using the absolute neph path:

```
PATH=$HOME/.local/bin:$PATH neph integration hook gemini
→ /absolute/path/to/neph integration hook gemini
```

The absolute path is detected via `detectNephBin()` (see design.md). The
replacement is done on the template in-memory; template files on disk are
unchanged.

## Install Behavior (per agent)

1. Read template from `integration.templatePath`.
2. Substitute command strings with absolute binary path.
3. Read existing global config (or `{}` if file absent).
4. Merge using existing `mergeHooks` / `mergeCopilot` logic.
5. Write updated config to `globalConfigPath`.
6. Print: `<agent>: installed → <path>` to stdout.

For claude: print `claude: skip (use alias — see below)`.

After all agents, print the shell alias block.

## Uninstall Behavior (per agent)

1. Read template from `integration.templatePath` (for matching).
2. Read existing global config; if absent, skip with `<agent>: nothing to remove`.
3. Unmerge using `unmergeHooks` / `unmergeCopilot`.
4. If resulting config is empty (`{}`), remove the file.
5. Otherwise write the cleaned config.
6. Print: `<agent>: removed → <path>` or `<agent>: nothing to remove`.

## Shell Alias Output

After install, stdout prints:

```
Add to your shell config (~/.zshrc, ~/.bashrc, etc.):

  alias claude='claude --settings "$(neph print-settings claude)"'
  alias codex='codex --enable codex_hooks'
```

The `codex` alias adds `--enable codex_hooks` because Codex requires this
feature flag to activate hook processing; it's off by default.

No alias is needed for gemini or cursor — global config is sufficient.

## Single-Agent Install

`neph install gemini` installs only the gemini integration. Shell alias output
is scoped to the requested agent.

`neph install claude` prints only the alias block (nothing to write).

## Error Cases

| Condition                      | stderr                                        | Exit |
|--------------------------------|-----------------------------------------------|------|
| Unknown agent name             | `Unknown integration: <name>`                 | 1    |
| $HOME not set                  | `neph install: $HOME is not set`              | 1    |
| Cannot write global config     | `Cannot write <path>: <err>. Check perms.`    | 1    |
| Template missing               | `Cannot read <path>: <err>`                   | 1    |

## Gemini Warning

After installing gemini, append to stdout:

```
gemini: warning — Gemini bug #23138: theme changes may overwrite
~/.gemini/settings.json. Re-run 'neph install gemini' after any theme change.
```

## Idempotency

Running `neph install` multiple times is safe. The merge logic deduplicates
entries by command string (via `normalizeCommand` + `hookEntryMatches`).

## Notes

- `neph install` does not restart or signal any agent process.
- `neph install` does not require a Neovim transport (`$NVIM` not needed).
- Running `neph install` after a neph update re-writes the global configs with
  the new binary path and any template changes. This is the intended upgrade path.
