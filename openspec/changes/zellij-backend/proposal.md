# Zellij Backend

## What

Add an explicit Zellij backend so AI agents run in Zellij panes instead of Neovim splits or WezTerm panes. Users running Neovim inside Zellij can choose `backend = require("neph.backends.zellij")` to get agent panes in the same Zellij session.

## Why

- Zellij users want agents in Zellij panes for consistent layout and workflow
- Snacks (Neovim splits) and WezTerm are not sufficient for Zellij-native users
- No upstream contribution—work with Zellij's current CLI capabilities

## Scope

- New `lua/neph/backends/zellij.lua` implementing backend interface
- Session refactor: optional `backend.send()`, `backend.single_pane_only`
- Wezterm backend: add `send()` (extract from session)
- One agent pane at a time for Zellij (layout constraint)
- `ready_pattern` not supported; use configurable delay instead

## Out of Scope

- Multiple agent panes in Zellij
- Contributing to Zellij upstream
- Pattern-based ready detection for Zellij
