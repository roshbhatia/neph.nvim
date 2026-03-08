## ADDED Requirements

### Requirement: Extension agent send_adapter SHALL deliver prompts regardless of startup timing

The pi agent's `send_adapter` SHALL set `vim.g.neph_pending_prompt` whenever a pi terminal exists, without gating on `vim.g.pi_active`. The prompt MUST be available for pi's polling loop to consume once the extension finishes initializing.

#### Scenario: Prompt sent before pi_active is set

- **WHEN** a pi terminal exists but `vim.g.pi_active` is nil (pi still initializing)
- **AND** the user sends a prompt via the input dialog
- **THEN** `vim.g.neph_pending_prompt` is set to the prompt text
- **AND** the send_adapter returns true (preventing chansend fallback)
- **AND** pi picks up the prompt on its first poll after initialization

#### Scenario: Prompt sent after pi_active is set

- **WHEN** a pi terminal exists and `vim.g.pi_active` is truthy
- **AND** the user sends a prompt
- **THEN** `vim.g.neph_pending_prompt` is set to the prompt text
- **AND** pi picks it up on the next 500ms poll cycle

#### Scenario: Prompt does not fall through to chansend

- **WHEN** the pi send_adapter is called
- **THEN** the adapter MUST return true
- **AND** the default chansend fallback MUST NOT execute

### Requirement: Session cleanup SHALL clear pending prompt for extension agents

When a pi session is closed or killed, any pending prompt in `vim.g.neph_pending_prompt` MUST be cleaned up to prevent stale state.

#### Scenario: Pi terminal killed with pending prompt

- **WHEN** `vim.g.neph_pending_prompt` contains a prompt
- **AND** the user kills the pi terminal via session.close
- **THEN** `vim.g.neph_pending_prompt` is set to nil

#### Scenario: Pi session_shutdown clears prompt

- **WHEN** pi's extension fires session_shutdown
- **THEN** `vim.g.neph_pending_prompt` is unset via `neph unset`
