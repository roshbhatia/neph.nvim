## MODIFIED Requirements

### Requirement: Winbar shows current hunk status

The review UI left winbar SHALL display a CURRENT label prefix, followed by the hunk index, decision status, and keymap hints. The right winbar SHALL display PROPOSED. Both winbars SHALL be visible regardless of plugins like dropbar that override winbar.

#### Scenario: Winbar shows CURRENT label and hunk info
- **WHEN** the cursor is on hunk 2 of 5
- **AND** hunk 2 has been accepted
- **THEN** the left winbar displays `CURRENT  Hunk 2/5: accepted  ga=accept  gr=reject  gA=all  gR=reject-all  q=quit`

#### Scenario: Winbar visible with dropbar installed
- **WHEN** the review diff tab opens
- **THEN** both review windows SHALL set window/buffer-local variables to suppress dropbar (`vim.b.dropbar_disabled = true`)
- **AND** the left winbar shows CURRENT label with hunk info
- **AND** the right winbar shows PROPOSED

### Requirement: Diff windows show line numbers

Both the left (current) and right (proposed) diff windows SHALL have line numbers enabled.

#### Scenario: Line numbers visible in diff view
- **WHEN** the review diff tab opens
- **THEN** both windows SHALL have `number = true` set as a window-local option

### Requirement: Clean buffer names

Review buffers SHALL use clean pseudo-URI names instead of timestamped bracket-prefixed names.

#### Scenario: Buffer names use neph:// URIs
- **WHEN** the review diff tab opens for file `foo.ts`
- **THEN** the left buffer name SHALL be `neph://current/foo.ts`
- **AND** the right buffer name SHALL be `neph://proposed/foo.ts`
