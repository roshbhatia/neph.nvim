## ADDED Requirements

### Requirement: Finalize active review on Neovim exit

When Neovim exits (VimLeavePre), if a review is active, the system SHALL reject all undecided hunks with reason "Neovim exiting", finalize the session, and write the result file. This ensures the waiting agent receives a response instead of timing out.

#### Scenario: Neovim exits with active review

- **GIVEN** a review is active with 3 undecided hunks and 2 accepted
- **WHEN** Neovim receives `:qa!`
- **THEN** the 3 undecided hunks are rejected with reason "Neovim exiting"
- **AND** the result envelope is written to `result_path`
- **AND** `review_queue.on_complete()` is called

#### Scenario: Neovim exits with no active review

- **WHEN** Neovim exits and no review is active
- **THEN** the VimLeavePre hook is a no-op

### Requirement: Clean up orphaned review UI on agent kill

When an agent session is killed, if a review from that agent is active in the UI, the review tab SHALL be closed and resources cleaned up.

#### Scenario: Agent crashes during active review

- **GIVEN** agent "claude" has an active review open
- **WHEN** the agent session is killed
- **THEN** the review UI tab is closed
- **AND** signs, autocmds, and diffopt are restored
- **AND** the review queue advances to the next item
