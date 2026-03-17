## MODIFIED Requirements

### Requirement: Keymap-based hunk navigation and decisions

The review UI SHALL present hunks in a vimdiff tab with buffer-local keymaps for accepting and rejecting individual hunks. Users MUST be able to navigate freely between hunks using standard Vim diff navigation and make decisions in any order. The review SHALL NOT auto-finalize when all hunks are decided. The UI SHALL be opened by `neph-cli review` via `review.open` RPC and SHALL return the decision envelope to the RPC caller when finalized.

#### Scenario: Accept a single hunk via keymap
- **WHEN** a review is open with 3 hunks and the cursor is on hunk 2
- **AND** the user presses `ga`
- **THEN** hunk 2 is marked as accepted
- **AND** signs are placed on the left buffer at the hunk's start line
- **AND** the cursor jumps to the next undecided hunk if any exist
- **AND** the review remains open

#### Scenario: Reject a hunk with reason via keymap
- **WHEN** a review is open and the cursor is on hunk 1
- **AND** the user presses `gr`
- **THEN** the user is prompted for a rejection reason via `vim.ui.input`
- **AND** hunk 1 is marked as rejected with the provided reason
- **AND** signs are placed on the left buffer

#### Scenario: Submit finalizes and returns envelope
- **WHEN** the user presses `gs` (submit)
- **THEN** `session.finalize()` is called
- **AND** the review envelope is returned to the RPC caller (not written to a temp file)
- **AND** the diff tab is cleaned up

#### Scenario: Quit rejects all undecided
- **WHEN** the user presses `q` or closes the tab with undecided hunks remaining
- **THEN** all undecided hunks are rejected with reason "User exited review"
- **AND** the review finalizes and returns the envelope to the RPC caller
