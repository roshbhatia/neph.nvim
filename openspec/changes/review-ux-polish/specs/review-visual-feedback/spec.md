# Review Visual Feedback

Visual feedback system for diff review UI using sign column indicators and virtual text hints.

## Capability

**review-visual-feedback** — Provide real-time visual feedback during diff review via signs, virtual text, and configurable icons.

## Rationale

The diff review UI needs to communicate state to the user: which hunk is active, what decisions have been made, and what actions are available. Signs and virtual text provide this feedback without modifying buffer content or requiring additional windows.

## ADDED Requirements

### Requirement: Sign column indicators for hunk status

The diff review UI SHALL display signs in the left buffer's sign column to indicate hunk status.

#### Scenario: Current hunk shows indicator

- **WHEN** diff review opens and cursor is on first hunk
- **THEN** sign `👉` (or configured `current` icon) is placed at the hunk's start line

#### Scenario: Accepted hunk shows indicator

- **WHEN** user presses `y` to accept a hunk
- **THEN** sign `✅` (or configured `accept` icon) replaces the current hunk indicator

#### Scenario: Rejected hunk without reason shows indicator

- **WHEN** user presses `n` and provides no reject reason (empty input)
- **THEN** sign `❌` (or configured `reject` icon) replaces the current hunk indicator

#### Scenario: Rejected hunk with reason shows indicator

- **WHEN** user presses `n` and provides a reject reason
- **THEN** sign `💬❌` (or configured `commented` icon) replaces the current hunk indicator

#### Scenario: Sign moves to next hunk on navigation

- **WHEN** user navigates to next hunk via `]c` or accepts/rejects current hunk
- **THEN** current hunk indicator (`👉`) is removed from previous hunk and placed at new hunk's start line

### Requirement: Virtual text hints at current hunk

The diff review UI SHALL display virtual text hints on the right buffer at the current hunk position.

#### Scenario: Terse keybinding hints shown by default

- **WHEN** diff review opens or user navigates to a hunk
- **THEN** virtual text `"[y]es [n]o [a]ll [d]eny [e]dit [?]help"` is displayed on a line within the current hunk

#### Scenario: Hunk counter shown alongside hints

- **WHEN** diff review opens or user navigates to a hunk
- **THEN** virtual text `"← hunk X/Y"` is displayed at the end of the first line of the current hunk

#### Scenario: Expanded help shown on toggle

- **WHEN** user presses `?` key while terse hints are visible
- **THEN** keybinding hint line is replaced with expanded text: `"y=accept | n=reject+reason | a=accept-all | d=reject-all | e=manual | [?] hide"`

#### Scenario: Help collapses on second toggle

- **WHEN** user presses `?` key while expanded help is visible
- **THEN** expanded help is replaced with terse keybinding hints

### Requirement: Configurable sign icons

The diff review UI SHALL allow users to override sign icons via plugin configuration.

#### Scenario: Default emoji signs used when no config

- **WHEN** user has not set `review_signs` in `neph.setup()`
- **THEN** signs use emoji defaults: `✅` accept, `❌` reject, `👉` current, `💬❌` commented

#### Scenario: Custom ASCII signs used from config

- **WHEN** user sets `neph.setup({ review_signs = { accept = "+", reject = "-", current = ">", commented = "*" } })`
- **THEN** diff review uses `+` for accepted hunks, `-` for rejected, `>` for current, `*` for commented

#### Scenario: Partial config merges with defaults

- **WHEN** user sets `neph.setup({ review_signs = { accept = "A" } })`
- **THEN** diff review uses `A` for accepted hunks and emoji defaults for other signs

### Requirement: Hunk range tracking

The diff review UI SHALL track the line range of each hunk for sign and virtual text placement.

#### Scenario: Hunk ranges parsed from diff metadata

- **WHEN** diff is opened between two buffers
- **THEN** system parses diff output to extract `{ start_line, end_line }` for each hunk in left buffer

#### Scenario: Sign placed at hunk start line

- **WHEN** current hunk indicator needs to be placed
- **THEN** sign is placed at the `start_line` from tracked hunk range

#### Scenario: Virtual text placed within hunk range

- **WHEN** virtual text hints need to be displayed
- **THEN** extmarks are placed on lines within the `start_line` to `end_line` range of current hunk

### Requirement: Virtual text uses DiagnosticInfo highlight

The diff review UI SHALL display virtual text hints with the `DiagnosticInfo` highlight group.

#### Scenario: Virtual text is visually distinct

- **WHEN** virtual text hints are displayed
- **THEN** they use `DiagnosticInfo` highlight group for bright, noticeable appearance
