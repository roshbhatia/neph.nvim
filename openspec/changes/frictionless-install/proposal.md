# Frictionless Install

## Problem

`neph integration toggle <agent>` writes hook config files into the current
project directory on every new project. This creates three categories of pain:

1. **Per-project friction**: every repo needs a manual toggle before neph works.
   Forgetting means no review gate, no session tracking, no checktime.

2. **Committed artifacts**: the config files (`,.neph/claude.json`,
   `.cursor/hooks.json`, etc.) either get committed to repos (polluting the
   project) or ignored (easy to forget, easy to lose).

3. **PATH fragility**: hook commands embed `PATH=$HOME/.local/bin:$PATH` as a
   workaround for `/bin/sh` not sourcing the user's shell profile. This leaks
   into every config file and every test assertion.

The toggle model was designed for per-project opt-in. That was the wrong unit.
The right unit is the user's machine. Once neph is installed, it should work
everywhere without any per-project configuration.

## Proposed Solution

Replace the toggle model with a two-part install model:

**1. `neph print-settings <agent>`** — a new subcommand that reads neph's
bundled template for `<agent>` and prints it as a JSON string to stdout.
No files written. Used in shell aliases.

**2. `neph install` / `neph uninstall`** — new commands that write neph hook
config to each agent's **global** config directory once, on install. These
replace per-project toggle for the common case.

The result:

| Agent  | Mechanism                              | Files written to project? |
|--------|----------------------------------------|---------------------------|
| Claude | `--settings` alias with inline JSON    | Never                     |
| Gemini | `~/.gemini/settings.json` (install)    | Never                     |
| Cursor | `~/.cursor/hooks.json` (install)       | Never                     |
| Codex  | `~/.codex/hooks.json` (install)        | Never                     |

After `neph install`, the user adds one alias per agent to their shell config
(printed by `neph install`). Every project works from that point forward.

## What Stays

- The existing `neph integration toggle` is kept as an opt-out/override
  mechanism for unusual cases (CI, shared machines, isolated repos).
- The per-project `.neph/claude.json` + `--settings` path introduced earlier
  this session remains available for projects that want explicit, committed
  integration.
- Hook handler logic (`neph integration hook <agent>`) is untouched. This is
  purely a change to *how hooks get registered*, not *what they do*.

## What Changes

- New CLI subcommands: `neph print-settings`, `neph install`, `neph uninstall`
- `neph install` detects the neph binary path and embeds it (absolute) in the
  hook command strings it writes, eliminating the PATH prefix workaround.
- `neph install` outputs ready-to-paste shell alias lines.
- Template files in `tools/*/` do not change — they remain the source of truth
  for hook structure and are used by both `print-settings` and `install`.

## Non-Goals

- MCP server integration (separate concern, tracked separately)
- Copilot (plugin model is different; not in scope here)
- Home-manager / Nix module (separate concern; this change is CLI-first)
