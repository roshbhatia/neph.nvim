## ADDED Requirements

### Requirement: Multiline input captures all lines
The input confirm callback SHALL read all buffer lines and join them with newlines, not just line 0.

#### Scenario: User types multiline prompt
- **GIVEN** the user types "line one" then Shift+Enter then "line two"
- **WHEN** they press Enter to confirm
- **THEN** the callback receives `"line one\nline two"`

### Requirement: Escape syntax for literal plus-tokens
`\+token` SHALL be preserved as literal `+token` in the output (backslash consumed, no expansion attempted).

#### Scenario: Escaped token
- **GIVEN** input `"what does \+file do?"`
- **WHEN** placeholders.apply() runs
- **THEN** output is `"what does +file do?"`

#### Scenario: Mix of escaped and real tokens
- **GIVEN** input `"fix +cursor but keep \+selection"`
- **WHEN** placeholders.apply() runs with cursor resolving to `@foo.lua:10`
- **THEN** output is `"fix @foo.lua:10 but keep +selection"`

### Requirement: Failed expansions are stripped
When a placeholder provider returns nil (e.g., `+cursor` on a non-file buffer), the raw `+token` text SHALL be removed from the output rather than left as a literal string.

#### Scenario: Token on non-file buffer
- **GIVEN** `+cursor` cannot resolve (current buffer is a terminal)
- **WHEN** placeholders.apply() runs on `"+cursor fix the thing"`
- **THEN** output is `"fix the thing"` (token and surrounding whitespace trimmed)

### Requirement: Clean default templates
The default prompt template for `api.ask()` in normal mode SHALL be `"+cursor "` (no leading space, no trailing colon). Visual mode SHALL be `"+selection "`.

#### Scenario: Normal mode ask default
- **GIVEN** user triggers ask in normal mode on `Taskfile.yml` line 41
- **WHEN** the input opens with the default prefilled
- **THEN** the default text is `"+cursor "` which expands to `"@Taskfile.yml:41 "`

### Requirement: Expansion values with special characters are safe
Placeholder expansion SHALL correctly handle values containing Lua pattern metacharacters (%, (, ), .), newlines, and unicode. No double-expansion SHALL occur.

#### Scenario: Selection containing percent signs
- **GIVEN** `+selection` returns `"100% done"`
- **WHEN** placeholders.apply() runs on `"check +selection"`
- **THEN** output is `"check 100% done"` (no pattern error)

#### Scenario: Expansion containing plus-token-like text
- **GIVEN** `+selection` returns `"use +file for context"`
- **WHEN** placeholders.apply() runs on `"explain +selection"`
- **THEN** output is `"explain use +file for context"` (no double expansion of +file)
