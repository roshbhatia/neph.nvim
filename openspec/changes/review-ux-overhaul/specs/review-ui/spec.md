## MODIFIED Requirements

### Requirement: Keymap-based hunk navigation and decisions

The review UI SHALL present hunks in a vimdiff tab with buffer-local keymaps for accepting and rejecting individual hunks. Users MUST be able to navigate freely between hunks using standard Vim diff navigation and make decisions in any order. The review SHALL NOT auto-finalize when all hunks are decided. Default keymaps SHALL use a `g`-prefix convention (`ga`, `gr`, `gA`, `gR`, `gu`, `gs`) instead of `<localleader>`-based bindings. All keymaps SHALL be overridable via `config.review_keymaps`.

#### Scenario: Accept a single hunk via keymap

- **WHEN** a review is open with 3 hunks and the cursor is on hunk 2
- **AND** the user presses `ga`
- **THEN** hunk 2 is marked as accepted
- **AND** a `✓` sign is placed on the left buffer at the hunk's `start_a` line
- **AND** no sign is placed on the right buffer
- **AND** the cursor jumps to the next undecided hunk if any exist
- **AND** the review remains open

#### Scenario: Reject a hunk with reason via keymap

- **WHEN** a review is open and the cursor is on hunk 1
- **AND** the user presses `gr`
- **THEN** the user is prompted for a rejection reason via `vim.ui.input`
- **AND** hunk 1 is marked as rejected with the provided reason
- **AND** a `✗` sign is placed on the left buffer only

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

#### Scenario: Submit review with gs

- **WHEN** all hunks are decided and the user presses `gs`
- **THEN** the review finalizes immediately

- **WHEN** undecided hunks remain and the user presses `gs`
- **THEN** a prompt appears offering to submit (reject undecided), jump to first undecided, or cancel

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
- **THEN** the left winbar displays mode label, hunk position, decision tally (✓3 ✗1 ?1), and compact keymap hints including `gs=submit` and `?=help`
- **AND** the right window SHALL NOT have a winbar

- **WHEN** a review is active and 2 reviews are queued
- **THEN** the left winbar SHALL additionally display "Review 1/3" to indicate queue position

#### Scenario: Sign placement aligns with diff highlight

- **WHEN** a hunk starts at `start_a` in the old file (1-indexed from `vim.diff`)
- **THEN** the sign is placed at line `start_a` (no offset)
- **AND** the sign visually aligns with Neovim's diff highlight block

#### Scenario: Line numbers visible on both panes

- **WHEN** the review diff tab is open
- **THEN** both left and right windows display line numbers
- **AND** line numbers persist even after window focus changes or diff sync events

#### Scenario: Config is read from config module not vim.g

- **WHEN** the user configures `review_keymaps` or `review_signs` in their `setup()` opts
- **THEN** the review UI SHALL read those values from `require("neph.config").current`
- **AND** `vim.g.neph_config` SHALL NOT be consulted

### Requirement: Post-write review visual distinction

The review UI SHALL visually distinguish post-write reviews from pre-write reviews.

#### Scenario: Post-write review winbar label

- **WHEN** a post-write review is open (mode = "post_write")
- **THEN** the left winbar SHALL display "POST-WRITE" instead of "CURRENT"
- **AND** the left buffer label SHALL be "neph://buffer-before/" and right SHALL be "neph://disk-after/"

#### Scenario: Pre-write review winbar label

- **WHEN** a pre-write review is open (mode = "pre_write" or default)
- **THEN** the left winbar SHALL display "CURRENT" as before
- **AND** the left buffer label SHALL be "neph://current/" and right SHALL be "neph://proposed/"

### Requirement: Review keymaps guard against invalid windows

Keymaps bound during review must not crash if the review windows have been closed or become invalid before the keymap fires.

#### Scenario: User closes review tab then presses a mapped key in another buffer

- **WHEN** a review keymap callback executes
- **AND** `ui_state.left_win` is no longer valid
- **THEN** the callback returns early without error

#### Scenario: User triggers keymap after finalization

- **WHEN** a review keymap callback executes
- **AND** `finalized` is true
- **THEN** the callback returns early without accessing ui_state or session

### Requirement: Async input callbacks guard against stale state

When a keymap opens an async dialog (e.g., `vim.ui.input`), the callback must handle the case where the review was finalized while the dialog was open.

#### Scenario: Review finalizes while reject-reason dialog is open

- **WHEN** the reject keymap opens `vim.ui.input`
- **AND** the user submits the review via another keymap before the input callback fires
- **THEN** the input callback detects `finalized == true` and returns early

### Requirement: Explicit diffopt for review tabs

The review UI SHALL set `diffopt` explicitly when opening a review tab to ensure consistent, high-quality diff rendering.

#### Scenario: Review tab sets diffopt

- **WHEN** a review diff tab is opened
- **THEN** `vim.o.diffopt` SHALL be set to `internal,filler,closeoff,indent-heuristic,inline:char,linematch:60,algorithm:histogram`
- **AND** the user's original `diffopt` value SHALL be saved

#### Scenario: Review tab restores diffopt on close

- **WHEN** a review diff tab is closed (via submit, quit, or tab close)
- **THEN** `vim.o.diffopt` SHALL be restored to the user's original value

### Requirement: Clean filler line rendering

The review UI SHALL set `fillchars` on both review windows to use a subtle fill character for diff filler lines.

#### Scenario: Filler lines use subtle character

- **WHEN** a review diff tab is open
- **THEN** both windows SHALL have `fillchars` set to include `diff:╌`
- **AND** filler lines (representing missing content) SHALL render with the `╌` character instead of the default `-`
