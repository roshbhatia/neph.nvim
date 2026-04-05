# Spec: neph integration toggle — review gate only

## Requirement

`neph integration toggle <agent>` should install only the **review gate hooks**
(PreToolUse/PostToolUse) to the project-level config path. Lifecycle hooks are
handled by the Nix module globally.

For non-Nix users (no home-manager module), the toggle continues to install
everything (backward compat) — there's no way to detect nix management from
the CLI, and installing both is still correct (idempotent with the nix module).

## The Real Change

The split is primarily in the **template files** and the **Nix module**, not in
the CLI behavior. `neph integration toggle` behavior is unchanged for non-Nix
users.

What changes: `neph integration status` output shows which hooks are installed
and at which scope (global vs project).

## Acceptance Criteria

- `neph integration toggle claude` in a project writes only PreToolUse/PostToolUse
  to `.claude/settings.json` (review gate). SessionStart/End/etc. are in the Nix
  module, not installed by toggle.
- Actually: since non-Nix users need full installation, the template stays merged.
  The distinction is captured in template metadata (`_kind`), used by the Nix
  module to filter.
- `neph integration status --show-config` clearly shows what's installed.
