# Spec: neph.nvim Home-Manager Module

## Requirement

`neph.nvim/flake.nix` exports `homeManagerModules.default` — a home-manager module
that installs lifecycle hooks for all enabled agent integrations.

## Options Interface

```nix
programs.neph = {
  enable = lib.mkEnableOption "neph.nvim integration lifecycle hooks";
  integrations = {
    claude  = lib.mkEnableOption "claude lifecycle hooks"  // { default = true; };
    gemini  = lib.mkEnableOption "gemini lifecycle hooks"  // { default = true; };
    cursor  = lib.mkEnableOption "cursor lifecycle hooks"  // { default = true; };
    copilot = lib.mkEnableOption "copilot lifecycle hooks" // { default = true; };
    codex   = lib.mkEnableOption "codex lifecycle hooks"   // { default = true; };
  };
};
```

## Behavior

When `programs.neph.enable = true`:

- **Claude**: merges lifecycle hooks into `programs.claude-code.settings.hooks`
  (SessionStart, SessionEnd, UserPromptSubmit, Stop). Uses `lib.mkMerge` so it
  composes with existing claude-code config.

- **Gemini**: writes `~/.gemini/settings.json` with lifecycle hooks
  (SessionStart, SessionEnd, BeforeAgent, AfterAgent). Does NOT touch
  `~/.config/gemini/settings.toml` (MCP config — separate file).

- **Cursor**: writes `~/.cursor/hooks.json` with all cursor hooks
  (afterFileEdit, beforeShellExecution, beforeMCPExecution). Cursor has no
  project-level hooks — global is the only option.

- **Copilot**: writes `~/.copilot/hooks.json` with sessionStart/sessionEnd
  lifecycle hooks only. preToolUse review gate stays in project-level toggle.

- **Codex**: writes `~/.codex/hooks.json` with UserPromptSubmit/Stop
  lifecycle hooks.

## File Ownership

The module uses `force = true` for files it manages so that if the user also
runs `neph integration toggle`, the project-level file wins (different path).
For the global files, nix owns them.

## Acceptance Criteria

- `flake.nix` exports `homeManagerModules.default`
- `nix/hm-module.nix` contains the full module implementation
- Module composes cleanly with `programs.claude-code` (no conflicts)
- Module is tested via a `nix flake check` devShell or simple eval test
