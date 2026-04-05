# nix/hm-module.nix
# home-manager module for neph.nvim integration lifecycle hooks.
# Reads template JSON files from tools/, filters to _kind == "lifecycle" entries,
# strips the _kind metadata, and wires hooks into agent config files.
{ config, lib, ... }:
let
  cfg = config.programs.neph;
  toolsRoot = ./.. + "/tools";

  templateFile = agent:
    let
      filename =
        if agent == "cursor" || agent == "copilot" || agent == "codex"
        then "hooks.json"
        else "settings.json";
    in
      toolsRoot + "/${agent}/${filename}";

  isLifecycle = entry: (entry._kind or "review") == "lifecycle";
  stripKind = entry: builtins.removeAttrs entry [ "_kind" ];

  # Returns the lifecycle-only hooks in the format appropriate for the agent.
  # For hooks-style agents (claude/gemini/cursor/codex): returns an attrset of event → entries.
  # For copilot (array-style): returns a filtered list.
  lifecycleHooksFor = agent:
    let
      template = builtins.fromJSON (builtins.readFile (templateFile agent));
      raw = template.hooks or { };
    in
      if builtins.isAttrs raw
      then
        # Hooks-style: attrset keyed by event name
        lib.filterAttrs (_event: entries: entries != [ ])
          (lib.mapAttrs
            (_event: entries: map stripKind (builtins.filter isLifecycle entries))
            raw)
      else
        # Copilot array-style
        map stripKind (builtins.filter isLifecycle raw);

in
{
  options.programs.neph = {
    enable = lib.mkEnableOption "neph.nvim integration lifecycle hooks";

    integrations = lib.mapAttrs
      (_name: _v: lib.mkEnableOption "integration" // { default = true; })
      {
        claude = { };
        gemini = { };
        cursor = { };
        copilot = { };
        codex = { };
      };
  };

  config = lib.mkIf cfg.enable {
    # Wire Claude lifecycle hooks into programs.claude-code.settings.hooks.
    # The review gate hooks (PreToolUse/PostToolUse) are managed per-project
    # by `neph integration toggle claude`.
    programs.claude-code.settings.hooks =
      lib.mkIf cfg.integrations.claude (lifecycleHooksFor "claude");

    home.file = lib.mkMerge [
      # Gemini: write lifecycle-only hooks to .gemini/settings.json
      (lib.mkIf cfg.integrations.gemini {
        ".gemini/settings.json".text = builtins.toJSON {
          hooks = lifecycleHooksFor "gemini";
        };
      })

      # Cursor: write all cursor hooks (all are lifecycle) to .cursor/hooks.json
      (lib.mkIf cfg.integrations.cursor {
        ".cursor/hooks.json".text = builtins.toJSON {
          hooks = lifecycleHooksFor "cursor";
        };
      })

      # Copilot: write sessionStart/sessionEnd hooks to .copilot/hooks.json
      (lib.mkIf cfg.integrations.copilot {
        ".copilot/hooks.json".text = builtins.toJSON {
          hooks = lifecycleHooksFor "copilot";
        };
      })

      # Codex: write UserPromptSubmit/Stop hooks to .codex/hooks.json
      (lib.mkIf cfg.integrations.codex {
        ".codex/hooks.json".text = builtins.toJSON {
          hooks = lifecycleHooksFor "codex";
        };
      })
    ];
  };
}
