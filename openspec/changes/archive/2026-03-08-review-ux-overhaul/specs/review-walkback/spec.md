## ADDED Requirements

### Requirement: Clear a hunk decision back to undecided

The engine session SHALL provide a `clear_at(idx)` method that resets a hunk's decision to undecided (nil). The UI SHALL bind this to the `gu` keymap. Clearing a decision SHALL update signs on both buffers and the winbar tally.

#### Scenario: Clear an accepted hunk

- **WHEN** hunk 2 has been accepted
- **AND** the user navigates to hunk 2 and presses `gu`
- **THEN** `get_decision(2)` returns nil
- **AND** `is_complete()` returns false
- **AND** the signs on both left and right buffers for hunk 2 are removed
- **AND** the winbar tally updates to reflect one more undecided hunk

#### Scenario: Clear a rejected hunk

- **WHEN** hunk 3 has been rejected with reason "wrong approach"
- **AND** the user presses `gu` on hunk 3
- **THEN** `get_decision(3)` returns nil
- **AND** the rejection reason is discarded

#### Scenario: Clear on an already undecided hunk is a no-op

- **WHEN** hunk 1 has no decision
- **AND** the user presses `gu` on hunk 1
- **THEN** `get_decision(1)` remains nil
- **AND** no error occurs

### Requirement: Flip decisions with ga/gr on already-decided hunks

The UI SHALL allow `ga` and `gr` to overwrite existing decisions. Pressing `ga` on a rejected hunk SHALL change it to accepted. Pressing `gr` on an accepted hunk SHALL change it to rejected (prompting for reason).

#### Scenario: Flip a rejected hunk to accepted

- **WHEN** hunk 2 has been rejected
- **AND** the user presses `ga` on hunk 2
- **THEN** `get_decision(2)` returns accept
- **AND** signs update on both buffers to reflect acceptance

#### Scenario: Flip an accepted hunk to rejected

- **WHEN** hunk 1 has been accepted
- **AND** the user presses `gr` on hunk 1
- **THEN** the user is prompted for a rejection reason
- **AND** `get_decision(1)` returns reject with the provided reason

### Requirement: Explicit submit via CR keymap

The review SHALL NOT auto-finalize when all hunks are decided. The user MUST press `<CR>` to submit the review. The submit flow SHALL handle undecided hunks gracefully.

#### Scenario: Submit with all hunks decided

- **WHEN** all hunks have decisions (accepted or rejected)
- **AND** the user presses `<CR>`
- **THEN** the review finalizes immediately
- **AND** the result envelope is written
- **AND** the diff tab is closed

#### Scenario: Submit with undecided hunks prompts confirmation

- **WHEN** 3 of 7 hunks are undecided
- **AND** the user presses `<CR>`
- **THEN** a prompt appears: "3 undecided hunks will be rejected. Submit / Jump to first / Cancel"
- **AND** selecting "Submit" rejects all undecided and finalizes
- **AND** selecting "Jump to first" moves cursor to the first undecided hunk
- **AND** selecting "Cancel" returns to the review without changes

#### Scenario: gA does not finalize

- **WHEN** hunks 1 and 3 are rejected and hunks 2, 4, 5 are undecided
- **AND** the user presses `gA`
- **THEN** hunks 2, 4, and 5 are marked as accepted
- **AND** the review remains open with signs and winbar updated
- **AND** the user can still navigate and change decisions

#### Scenario: gR does not finalize

- **WHEN** hunks 1 and 2 are accepted and hunks 3, 4 are undecided
- **AND** the user presses `gR`
- **THEN** hunks 3 and 4 are marked as rejected
- **AND** the review remains open
