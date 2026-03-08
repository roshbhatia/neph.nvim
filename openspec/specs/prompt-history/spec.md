## REMOVED Requirements

### Requirement: Per-agent JSON history persistence

The per-agent JSON file history, history picker UI, and history index tracking MUST be removed. Agents maintain their own conversation history. Only in-memory last-prompt tracking (for resend) SHALL be retained.

#### Scenario: History module no longer exists

- **WHEN** `require("neph.internal.history")` is called
- **THEN** it errors because the module has been deleted

#### Scenario: Resend still works without history

- **WHEN** a prompt has been sent to an agent via neph input
- **AND** the user calls `M.resend()`
- **THEN** the last prompt is resent using `terminal.get_last_prompt()`
- **AND** no JSON file is read or written

#### Scenario: No history keymap exists

- **WHEN** neph is set up with default keymaps
- **THEN** no keymap for history picker is registered

#### Scenario: Last prompt tracking is in-memory only

- **WHEN** `terminal.set_last_prompt("claude", "fix the bug")`
- **AND** `terminal.get_last_prompt("claude")` is called
- **THEN** it returns "fix the bug"
- **AND** no file I/O occurs
