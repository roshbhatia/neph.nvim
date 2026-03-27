## ADDED Requirements

### Requirement: gate-winbar-set

When gate transitions to `hold`, set `vim.wo[win].winbar` on the currently focused window to include `%#WarningMsg# ⏸ NEPH HOLD %*`. When gate transitions to `bypass`, include `%#DiagnosticError# ⚡ NEPH BYPASS %*`. The indicator is appended to any existing winbar content with a two-space separator; if winbar is empty, it is set directly.

### Requirement: gate-winbar-clear

When gate returns to normal (release), restore the affected window's winbar to its pre-indicator value (stored at set time). Uses `pcall` in case the window has closed.

### Requirement: gate-winbar-isolation

Only the window that was current at the time of the gate transition is affected. Does not modify `vim.o.winbar` (global). Does not affect windows opened after the gate was set.

### Requirement: gate-winbar-module

`lua/neph/internal/gate_ui.lua` exposes `M.set(state, win)` and `M.clear()`. State is `"hold"` or `"bypass"`. `lua/neph/api.lua` calls these from `M.gate_hold`, `M.gate_bypass`, and `M.gate_release` (and the cycle path in `M.gate`).
