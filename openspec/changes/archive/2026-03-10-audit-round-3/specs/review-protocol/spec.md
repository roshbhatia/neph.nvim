## MODIFIED Requirements

### Requirement: Post-write partial merge trailing newline check

The `_apply_post_write` function SHALL correctly check whether merged content ends with a newline.

#### Scenario: Content does not end with newline

- **WHEN** the user accepts some hunks in a post-write review
- **AND** the merged content does not end with `\n`
- **THEN** a trailing newline SHALL be appended before writing

#### Scenario: Content already ends with newline

- **WHEN** the merged content already ends with `\n`
- **THEN** no additional newline SHALL be appended

## ADDED Requirements

### Requirement: Engine finalize bounds safety

The review engine finalize step SHALL not access out-of-bounds indices in the new_lines array.

#### Scenario: Hunk metadata exceeds actual line count

- **WHEN** an accepted hunk references line indices beyond `#new_lines`
- **THEN** the engine SHALL clamp access to `#new_lines`
- **AND** SHALL not insert nil values into the result
