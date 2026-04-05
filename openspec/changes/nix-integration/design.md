# Design: Nix Integration

## Core Decision: flake module + template metadata

neph.nvim's `flake.nix` gains a `homeManagerModules.default` export. A new
`nix/hm-module.nix` file contains the module. Template JSON files gain `_kind`
metadata on each hook entry so the module can filter to lifecycle-only hooks.

No changes to CLI behavior for non-Nix users.

## File Map

```
neph.nvim/
  flake.nix                    (modify) — add homeManagerModules.default output
  nix/
    hm-module.nix              (new)    — programs.neph home-manager module
  tools/
    claude/settings.json       (modify) — add _kind metadata to hook entries
    gemini/settings.json       (modify) — add _kind metadata
    cursor/hooks.json          (modify) — add _kind metadata
    copilot/hooks.json         (modify) — add _kind metadata
    codex/hooks.json           (modify) — add _kind metadata
```

## Template Metadata Design

Hook entries get a `_kind` field. The CLI strips `_kind` before writing to disk
(it's neph-internal metadata, not passed to agents). The Nix module reads
templates directly and filters by kind.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "_kind": "lifecycle",
        "hooks": [{ "type": "command", "command": "neph integration hook claude" }]
      }
    ],
    "PreToolUse": [
      {
        "_kind": "review",
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [{ "type": "command", "command": "neph integration hook claude" }]
      }
    ]
  }
}
```

The `_kind` field must be stripped before writing config (Claude Code / Gemini
would reject unknown fields or treat them as matchers).

## Nix Module Structure

```nix
# nix/hm-module.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.neph;
  toolsRoot = ./../tools;

  # Read template JSON, filter to lifecycle hooks, strip _kind
  lifecycleHooksFor = agent:
    let
      templatePath = toolsRoot + "/${agent}/${if agent == "cursor" || agent == "copilot" || agent == "codex"
                                              then "hooks.json"
                                              else "settings.json"}";
      template = builtins.fromJSON (builtins.readFile templatePath);
      filterEntry = entry: entry._kind or "review" == "lifecycle";
      stripKind = entry: builtins.removeAttrs entry ["_kind"];
      filterHooks = hooks:
        lib.mapAttrs (_event: entries:
          map stripKind (builtins.filter filterEntry entries)
        ) hooks;
    in
      # For hooks-style (object): filter each event's entries
      if builtins.isAttrs (template.hooks or null)
      then filterHooks template.hooks
      # For copilot array-style: filter entries directly  
      else map stripKind (builtins.filter filterEntry (template.hooks or []));
in
{
  options.programs.neph = {
    enable = lib.mkEnableOption "neph.nvim integration lifecycle hooks";
    integrations = lib.mapAttrs (_n: _v:
      lib.mkEnableOption "integration" // { default = true; }
    ) { claude = {}; gemini = {}; cursor = {}; copilot = {}; codex = {}; };
  };

  config = lib.mkIf cfg.enable {
    programs.claude-code.settings.hooks = lib.mkIf cfg.integrations.claude
      (lifecycleHooksFor "claude");

    home.file = lib.mkMerge [
      (lib.mkIf cfg.integrations.gemini {
        ".gemini/settings.json".text = builtins.toJSON {
          hooks = lifecycleHooksFor "gemini";
        };
      })
      (lib.mkIf cfg.integrations.cursor {
        ".cursor/hooks.json".text = builtins.toJSON {
          hooks = lifecycleHooksFor "cursor";
        };
      })
      (lib.mkIf cfg.integrations.copilot {
        ".copilot/hooks.json".text = builtins.toJSON {
          hooks = lifecycleHooksFor "copilot";
        };
      })
      (lib.mkIf cfg.integrations.codex {
        ".codex/hooks.json".text = builtins.toJSON {
          hooks = lifecycleHooksFor "codex";
        };
      })
    ];
  };
}
```

## flake.nix Addition

```nix
homeManagerModules = {
  default = import ./nix/hm-module.nix;
};
```

## CLI Changes: strip _kind on write

In `integration.ts`, the `mergeHooks` / `mergeCopilot` functions must strip
`_kind` from entries before writing to disk:

```typescript
function stripKind(entry: any): any {
  const { _kind, ...rest } = entry;
  return rest;
}
```

Applied in `mergeHooks` and `mergeCopilot` before pushing entries.

## sysinit Integration

After this change, sysinit's `flake.nix` adds:
```nix
inputs.neph-nvim.url = "github:roshbhatia/neph.nvim";
```

And somewhere in `modules/home/programs/llm/default.nix` or a new `neph.nix`:
```nix
{ inputs, ... }: {
  imports = [ inputs.neph-nvim.homeManagerModules.default ];
  programs.neph.enable = true;
}
```

The existing manually-added hooks in `claude.nix` can be removed — the module
handles them.
