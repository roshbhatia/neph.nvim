# Nix Integration

## Problem

neph's hook-based integrations need to be configured in each AI tool's config
file. For users who manage their environment with Nix/home-manager, this creates
a fundamental conflict: the config files are symlinks into the read-only Nix
store. `neph integration toggle` can't write to them, and manually adding the
hooks to the Nix config couples neph's hook format to the user's system config —
every time neph changes a hook command or adds a new lifecycle event, the user
has to edit their Nix files and rebuild.

The problem isn't permissions (sudo won't help against `/nix/store`). The problem
is there's no clean interface between neph's imperative toggle model and Nix's
declarative config model.

There's a secondary problem too: the current `neph integration toggle` template
files mix lifecycle signals (SessionStart/End → set active/running state) with
the review gate (PreToolUse → cupcake → vimdiff). These serve completely different
purposes and have different ownership:

- **Lifecycle signals** are infrastructure. They should always be on whenever
  neph is installed. They don't block anything; they just notify Neovim that an
  agent session exists.
- **The review gate** is a project choice. You want review for this codebase,
  not all codebases. It's opt-in per project.

Mixing them into one template means toggling the review gate also toggles the
lifecycle signals, and installing lifecycle signals globally requires writing to
nix-managed files.

## Research Findings

### The hooks file / tool settings split

Inspecting the sysinit repo reveals that for most tools, the hooks config file is
already separate from what Nix manages:

| Tool     | Hooks file              | sysinit manages      | Conflict? |
|----------|-------------------------|----------------------|-----------|
| cursor   | `~/.cursor/hooks.json`  | `cli-config.json`    | none      |
| copilot  | `~/.copilot/hooks.json` | `cli/config.json`    | none      |
| codex    | `~/.codex/hooks.json`   | nothing              | none      |
| gemini   | `~/.gemini/settings.json` | `~/.config/gemini/settings.toml` | none |
| claude   | `~/.claude/settings.json` | via `programs.claude-code` | **CONFLICT** |

Claude is the only tool where the hooks file and the Nix-managed config file are
the same path. Every other tool's hooks file is untouched by sysinit — neph
already writes them imperatively without conflict.

### How Claude Code resolves settings

Claude Code merges settings from two sources:
- `~/.claude/settings.json` (global user settings)
- `.claude/settings.json` (project-level settings)

Project settings take precedence over global. This means lifecycle hooks can live
at the user level (nix-managed) and the review gate can live at the project level
(neph-managed), and they coexist without conflict.

### neph.nvim already has a flake.nix

`neph.nvim/flake.nix` exists but only exports `devShells`. Adding
`homeManagerModules.default` is straightforward and gives Nix users a proper
interface without changing anything for non-Nix users.

## Proposed Solution

### Core principle: split by purpose, split by scope

```
LIFECYCLE SIGNALS              REVIEW GATE
─────────────────              ──────────────────────────
SessionStart/End               PreToolUse → cupcake eval
Stop/UserPromptSubmit          PostToolUse → checktime
agent running state

Purpose: notify Neovim          Purpose: intercept writes
Scope: user-global              Scope: per-project
Owner: Nix module or            Owner: neph integration toggle
       direct write to ~/       
Frequency: always on            Frequency: opt-in per repo
Rebuild to change: fine         Toggle instantly: required
```

### Change 1: Split hook templates by purpose

Add `kind` metadata to each hook entry in template JSON files, or maintain two
separate template files per agent:

```
tools/claude/settings.json          (current: mixed)
tools/claude/settings-lifecycle.json  (new: SessionStart/End/Stop/UserPromptSubmit)
tools/claude/settings-review.json     (new: PreToolUse/PostToolUse)
```

`neph integration toggle claude` installs only the review gate template.
`neph integration install claude` installs lifecycle hooks globally (can write
to `~/` paths directly, since those aren't Nix-managed for most tools).

For Claude specifically, `neph integration install claude --nix` prints the Nix
attribute set to add to `programs.claude-code.settings.hooks` rather than trying
to write the file.

### Change 2: neph.nvim exports a home-manager module

`neph.nvim/flake.nix` gains `homeManagerModules.default`:

```nix
homeManagerModules.default = { config, lib, ... }:
  let
    cfg = config.programs.neph;
    lifecycleHooks = agent: [
      { hooks = [{ type = "command"; command = "neph integration hook ${agent}"; }]; }
    ];
  in {
    options.programs.neph = {
      enable = lib.mkEnableOption "neph.nvim integration lifecycle hooks";
      integrations = {
        claude  = lib.mkEnableOption "claude lifecycle hooks"  // { default = true; };
        gemini  = lib.mkEnableOption "gemini lifecycle hooks"  // { default = true; };
        cursor  = lib.mkEnableOption "cursor lifecycle hooks"  // { default = true; };
        copilot = lib.mkEnableOption "copilot lifecycle hooks" // { default = true; };
        codex   = lib.mkEnableOption "codex lifecycle hooks"   // { default = true; };
      };
    };

    config = lib.mkIf cfg.enable {
      # Claude: merge into programs.claude-code if it exists
      programs.claude-code.settings.hooks = lib.mkIf cfg.integrations.claude {
        SessionStart    = lifecycleHooks "claude";
        SessionEnd      = lifecycleHooks "claude";
        UserPromptSubmit = lifecycleHooks "claude";
        Stop            = lifecycleHooks "claude";
      };

      # Other tools: write hooks files directly (no Nix conflict)
      home.file = lib.mkMerge [
        (lib.mkIf cfg.integrations.gemini {
          ".gemini/settings.json".text = builtins.toJSON {
            hooks = {
              SessionStart = lifecycleHooks "gemini";
              SessionEnd   = lifecycleHooks "gemini";
              BeforeAgent  = lifecycleHooks "gemini";
              AfterAgent   = lifecycleHooks "gemini";
            };
          };
        })
        (lib.mkIf cfg.integrations.cursor {
          ".cursor/hooks.json".text = builtins.toJSON {
            hooks.afterFileEdit        = [{ command = "neph integration hook cursor"; }];
            hooks.beforeShellExecution = [{ command = "neph integration hook cursor"; }];
            hooks.beforeMCPExecution   = [{ command = "neph integration hook cursor"; }];
          };
        })
        (lib.mkIf cfg.integrations.copilot {
          ".copilot/hooks.json".text = builtins.toJSON {
            hooks = [
              { event = "sessionStart"; command = "neph integration hook copilot"; }
              { event = "sessionEnd";   command = "neph integration hook copilot"; }
            ];
          };
        })
        (lib.mkIf cfg.integrations.codex {
          ".codex/hooks.json".text = builtins.toJSON {
            hooks = {
              UserPromptSubmit = lifecycleHooks "codex";
              Stop             = lifecycleHooks "codex";
            };
          };
        })
      ];
    };
  };
```

sysinit then imports neph.nvim as a flake input:

```nix
# flake.nix
inputs.neph-nvim.url = "github:roshbhatia/neph.nvim";

# modules/home/programs/llm/default.nix or a new neph.nix
{ inputs, ... }: {
  imports = [ inputs.neph-nvim.homeManagerModules.default ];
  programs.neph.enable = true;
  # integrations default to true; disable any you don't want
  programs.neph.integrations.copilot = false;
}
```

### Change 3: neph integration toggle = review gate only

`neph integration toggle claude` no longer installs SessionStart/End hooks.
It only installs PreToolUse/PostToolUse (the review gate) to the project-level
`.claude/settings.json`. This is always a local file in the project repo, never
a symlink into the Nix store.

The user experience becomes:

```bash
# One-time global setup (via Nix rebuild)
programs.neph.enable = true
→ lifecycle hooks installed for all enabled agents

# Per-project opt-in
cd my-project
neph integration toggle claude
→ review gate added to .claude/settings.json
→ commit this file to opt the whole team in
```

### What this looks like end-to-end

```
GLOBAL (nix-managed, always on)           PER-PROJECT (neph toggle, opt-in)
──────────────────────────────────        ──────────────────────────────────
~/.claude/settings.json                   .claude/settings.json
  SessionStart → setActive                  PreToolUse → cupcake → review
  SessionEnd   → unsetActive                PostToolUse → checktime
  UserPromptSubmit → setRunning
  Stop → unsetRunning + checktime

~/.gemini/settings.json                   .gemini/settings.json (future)
  SessionStart/End/Before/AfterAgent        BeforeTool → cupcake → review

~/.cursor/hooks.json                      .cursor/hooks.json
  afterFileEdit → checktime                 (cursor is post-write only;
  beforeShell/MCP → cupcake gate            no review gate to add)

~/.copilot/hooks.json                     .copilot/hooks.json (future)
  sessionStart/End                          preToolUse → cupcake → review

~/.codex/hooks.json                       .codex/hooks.json (future)
  UserPromptSubmit/Stop                     PreToolUse → cupcake → review
```

Note: cursor hooks live at the global level because Cursor doesn't have
project-level hook config — all hooks are user-global.

## Non-Goals

- Migrating existing users to the split template format automatically
- Supporting every possible Nix setup (flake-free, channels, etc.) — flakes only
- Making `neph integration toggle` nix-aware (it stays purely imperative)
- The sysinit-internal approach (adding `sysinit.llm.neph.enable` option) — using
  the proper flake module is cleaner and decoupled

## Success Criteria

- `programs.neph.enable = true` in sysinit installs lifecycle hooks for all agents
  after a `home-manager switch`, without touching any project config files
- `neph integration toggle claude` in a project adds only the review gate to
  `.claude/settings.json`; lifecycle hooks are unaffected
- Non-Nix users: no behavior change. `neph integration toggle` still works as before
  (installs both lifecycle + review gate together via the merged template)
- The Nix module is versioned with neph.nvim — updating the flake input picks up
  new hook formats automatically
- Cursor hooks (global only) work correctly via home-manager without any project-level toggle

---

_Last updated: 2026-04-05_
