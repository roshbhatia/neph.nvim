## ADDED Requirements

### Requirement: Preview shows context lines
The review picker preview SHALL show 3 lines of context before and after the hunk lines, clamped to buffer boundaries.

#### Scenario: Hunk in middle of file
- **WHEN** a hunk spans lines 10-12 of a 50-line file
- **THEN** the preview shows lines 7-15 (3 before + hunk + 3 after)

#### Scenario: Hunk at start of file
- **WHEN** a hunk spans lines 1-3
- **THEN** the preview shows lines 1-6 (no lines before, 3 after)

#### Scenario: Hunk at end of file
- **WHEN** a hunk spans the last 2 lines of a 20-line file
- **THEN** the preview shows lines 15-20 (3 before, no lines after)

### Requirement: Preview highlights changed lines with diff colors
The review picker preview SHALL highlight the changed lines (non-context) with diff highlight groups on top of filetype syntax highlighting.

#### Scenario: Accept preview shows DiffAdd
- **WHEN** the user focuses the "Accept" option in the picker
- **THEN** the preview shows the proposed new lines highlighted with `DiffAdd`
- **AND** context lines have no diff highlight (only syntax)

#### Scenario: Reject preview shows no diff highlight
- **WHEN** the user focuses the "Reject" option in the picker
- **THEN** the preview shows the current old lines with syntax highlighting only
- **AND** no diff-specific coloring is applied (the user is keeping these lines)

### Requirement: Accept all and reject all use same preview as accept and reject
The "Accept all remaining" and "Reject all remaining" picker options SHALL show the same preview content as "Accept" and "Reject" respectively for the current hunk.

#### Scenario: Accept all preview matches accept
- **WHEN** the user focuses "Accept all remaining"
- **THEN** the preview is identical to "Accept" (proposed lines with DiffAdd + context)
