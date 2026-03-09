## MODIFIED Requirements

### Requirement: Keymap-based hunk navigation and decisions

The review UI SHALL present hunks in a vimdiff tab with buffer-local keymaps for accepting and rejecting individual hunks. Users MUST be able to navigate freely between hunks using standard Vim diff navigation and make decisions in any order. The review SHALL NOT auto-finalize when all hunks are decided.

#### Scenario: Accept a single hunk via keymap

- **WHEN** a review is open with 3 hunks and the cursor is on hunk 2
- **AND** the user presses `ga`
- **THEN** hunk 2 is marked as accepted
- **AND** signs are placed on both left and right buffers at the hunk's adjusted start lines
- **AND** the cursor jumps to the next undecided hunk if any exist
- **AND** the review remains open

#### Scenario: Reject a hunk with reason via keymap

- **WHEN** a review is open and the cursor is on hunk 1
- **AND** the user presses `gr`
- **THEN** the user is prompted for a rejection reason via `vim.ui.input`
- **AND** hunk 1 is marked as rejected with the provided reason
- **AND** signs are placed on both left and right buffers

#### Scenario: Accept all remaining undecided hunks

- **WHEN** a review is open with 5 hunks and hunks 1 and 3 are already decided
- **AND** the user presses `gA`
- **THEN** hunks 2, 4, and 5 are marked as accepted
- **AND** previously decided hunks 1 and 3 are NOT modified
- **AND** the review remains open with all signs and winbar updated

#### Scenario: Reject all remaining undecided hunks

- **WHEN** a review is open with undecided hunks and hunks 1, 2 already accepted
- **AND** the user presses `gR`
- **THEN** the user is prompted for a rejection reason
- **AND** only undecided hunks are marked as rejected
- **AND** hunks 1 and 2 remain accepted
- **AND** the review remains open

#### Scenario: Navigate between hunks freely

- **WHEN** a review is open with multiple hunks
- **AND** the user presses `]c` to go forward and `[c` to go back
- **THEN** the cursor moves between diff hunks using Vim's native diff navigation
- **AND** the winbar updates to show the current hunk index and status

#### Scenario: Quit rejects all undecided

- **WHEN** the user presses `q` or closes the tab with undecided hunks remaining
- **THEN** all undecided hunks are rejected with reason "User exited review"
- **AND** the review finalizes

#### Scenario: Random-access decisions in engine session

- **WHEN** a session has 4 hunks
- **AND** `accept_at(3)` is called, then `reject_at(1, "wrong")`
- **THEN** `get_decision(1)` returns reject with reason "wrong"
- **AND** `get_decision(2)` returns nil (undecided)
- **AND** `get_decision(3)` returns accept
- **AND** `is_complete()` returns false

#### Scenario: Winbar shows current hunk status with tally

- **WHEN** the cursor is on hunk 2 of 5
- **AND** hunk 2 has been accepted, 3 hunks accepted total, 1 rejected, 1 undecided
- **THEN** the winbar displays hunk status, decision tally (✓3 ✗1 ?1), and keymap hints including `<CR>=submit`

#### Scenario: Sign placement aligns with diff highlight

- **WHEN** a hunk starts at line 10 in the old file
- **THEN** the sign is placed at line 9 (start_a - 1, clamped to min 1)
- **AND** the sign visually aligns with Neovim's diff highlight block

#### Scenario: Line numbers visible on both panes

- **WHEN** the review diff tab is open
- **THEN** both left and right windows display line numbers
- **AND** line numbers persist even after window focus changes or diff sync events
