# Spec: Hook Template Split (lifecycle vs review gate)

## Requirement

Each agent's hook template must distinguish between two kinds of hooks:

- **Lifecycle hooks** — SessionStart/End, Stop, UserPromptSubmit, BeforeAgent/AfterAgent.
  These set active/running state in Neovim. They never block. They should be
  installed globally (user scope) and always on when neph is installed.

- **Review gate hooks** — PreToolUse/PostToolUse (or BeforeTool/AfterTool for Gemini).
  These intercept writes and invoke the cupcake review pipeline. They should be
  installed per-project via `neph integration toggle`.

## Current State

All hooks are mixed in a single template file per agent. `neph integration toggle`
installs everything at once to the project-level config path.

## Required Behavior

1. Template files stay as-is (backward compat for non-Nix users — toggle installs both).
2. Each hook entry in the template has a `"_kind": "lifecycle" | "review"` metadata
   field so tooling can filter.
3. The home-manager module uses only lifecycle hooks.
4. `neph integration toggle` continues to install both (unchanged behavior for non-Nix users).

## Acceptance Criteria

- `tools/claude/settings.json` entries each have `"_kind"` metadata
- Same for gemini, cursor, copilot, codex templates
- `_kind` is stripped before writing to actual config files (not passed to agents)
