# Shim Review Protocol (Modified)

Updates to `open_diff.lua` to support visual feedback via signs and virtual text.

## Capability

**shim-review-protocol** — Enhanced non-blocking diff UI with visual feedback.

## Rationale

The existing `open_diff.lua` provides functional hunk review but lacks visual feedback. This change extends the protocol to track hunk ranges, place signs, and display virtual text hints, making the review process transparent and discoverable.

## MODIFIED Requirements

### Requirement: open_diff.lua provides hunk-by-hunk review UI

The `open_diff.lua` script SHALL open a two-pane diff tab and allow users to accept or reject hunks via buffer-local keymaps. It SHALL track hunk decisions and display visual feedback for current hunk position and previous decisions.

#### Scenario: Diff opens with signs and hints

- **WHEN** `nvim.exec_lua(LUA_OPEN_DIFF, orig_path, prop_path, result_path, channel_id)` is called
- **THEN** two buffers are opened in diff mode with current hunk sign and virtual text hints visible

#### Scenario: Hunk ranges are tracked

- **WHEN** diff is opened
- **THEN** system parses diff metadata to build a table of `{ start_line, end_line }` for each hunk

#### Scenario: Current hunk indicator updates on navigation

- **WHEN** user navigates to next/previous hunk via `]c`/`[c` or via accept/reject action
- **THEN** current hunk sign (`❓`) is removed from old position and placed at new hunk's start line

#### Scenario: Accepted hunk shows persistent sign

- **WHEN** user presses `y` to accept a hunk
- **THEN** sign changes to `✅` and remains visible after navigating to next hunk

#### Scenario: Rejected hunk shows persistent sign

- **WHEN** user presses `n` to reject a hunk
- **THEN** sign changes to `❌` (no reason) or `📝` (with reason) and remains visible

#### Scenario: Virtual text hints move with current hunk

- **WHEN** user navigates to a different hunk
- **THEN** old virtual text extmarks are cleared and new ones are placed within the new hunk's line range

#### Scenario: Help toggle changes virtual text content

- **WHEN** user presses `?` while viewing terse hints
- **THEN** keybinding hint line is replaced with expanded help text

### Requirement: Sign definitions use namespace

The `open_diff.lua` script SHALL define signs within a dedicated sign group to avoid collisions with other plugins.

#### Scenario: Signs use neph_review group

- **WHEN** signs are defined
- **THEN** they are placed using sign group `neph_review`

#### Scenario: Signs are cleaned up on finalize

- **WHEN** review completes (accept-all, reject-all, or manual edit)
- **THEN** all signs in `neph_review` group are unplaced before closing the diff tab

### Requirement: Config integration

The `open_diff.lua` script SHALL read sign icon configuration from `vim.g.neph_config` and fall back to emoji defaults if absent.

#### Scenario: Config is read on diff open

- **WHEN** diff is opened
- **THEN** script checks `vim.g.neph_config.review_signs` for custom icons

#### Scenario: Missing config uses defaults

- **WHEN** `vim.g.neph_config` is nil or `review_signs` is absent
- **THEN** script uses emoji defaults: `✅❌❓📝`

#### Scenario: Partial config merges with defaults

- **WHEN** `vim.g.neph_config.review_signs` has only `{ accept = "A" }`
- **THEN** script uses `A` for accept sign and emoji defaults for others
