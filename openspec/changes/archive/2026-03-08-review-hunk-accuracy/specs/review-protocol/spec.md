## MODIFIED Requirements

### Requirement: Hunk ranges include both old-side and new-side coordinates
`compute_hunks()` SHALL return hunk ranges with four fields: `start_a`, `end_a` (old-file line range) and `start_b`, `end_b` (new-file line range). The UI SHALL use `start_a`/`end_a` to index the left (current) buffer and `start_b`/`end_b` to index the right (proposed) buffer.

#### Scenario: Replacement hunk (same line count)
- **WHEN** old line 5 is replaced with a new line 5
- **THEN** `compute_hunks()` returns `{ start_a=5, end_a=5, start_b=5, end_b=5 }`

#### Scenario: Addition hunk (new lines inserted)
- **WHEN** 2 new lines are inserted after old line 3
- **THEN** `compute_hunks()` returns a hunk with `start_a` pointing to the insertion point, `end_a = start_a` (no old lines removed), `start_b` and `end_b` spanning the 2 new lines

#### Scenario: Deletion hunk (old lines removed)
- **WHEN** old lines 7-9 are deleted (not present in new file)
- **THEN** `compute_hunks()` returns `{ start_a=7, end_a=9, start_b=<insertion point>, end_b=<insertion point - 1> }` (empty new-side range)

#### Scenario: UI uses correct range per buffer
- **WHEN** the UI shows the preview for a hunk
- **THEN** old lines are read from `left_buf[start_a..end_a]`
- **AND** new lines are read from `right_buf[start_b..end_b]`
- **AND** the cursor and sign are placed at `start_a` in the left buffer
