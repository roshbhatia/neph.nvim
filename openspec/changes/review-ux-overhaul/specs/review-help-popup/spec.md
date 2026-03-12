## ADDED Requirements

### Requirement: Help popup toggled with ?

The review UI SHALL provide a floating help window that displays all available keybindings, toggled with the `?` key.

#### Scenario: Open help popup

- **WHEN** a review is active and the user presses `?`
- **AND** no help popup is currently visible
- **THEN** a floating window SHALL appear centered in the review tab
- **AND** the window SHALL list all review keybindings with descriptions
- **AND** the window SHALL have a border with title "Neph Review"
- **AND** the window SHALL be non-editable (`buftype=nofile`, `modifiable=false`)

#### Scenario: Close help popup with ?

- **WHEN** the help popup is visible
- **AND** the user presses `?`
- **THEN** the help popup SHALL close
- **AND** focus SHALL return to the review buffer

#### Scenario: Close help popup with q or Escape

- **WHEN** the help popup is visible
- **AND** the user presses `q` or `<Esc>`
- **THEN** the help popup SHALL close
- **AND** the `q` keypress SHALL NOT trigger the review quit action

#### Scenario: Help popup content reflects configured keymaps

- **WHEN** the user has overridden `review_keymaps.accept` to `<leader>a`
- **THEN** the help popup SHALL display `<leader>a` instead of `ga` for the accept action

#### Scenario: Help popup does not interfere with review state

- **WHEN** the help popup is open
- **THEN** no review decisions SHALL be modified
- **AND** the review session SHALL remain active
- **AND** closing the popup SHALL not finalize the review

### Requirement: Help popup includes navigation keys

The help popup SHALL include Vim's native diff navigation keys (`]c`, `[c`) alongside the neph-specific keybindings, so users discover all available navigation in one place.

#### Scenario: Help content sections

- **WHEN** the help popup is displayed
- **THEN** it SHALL contain sections for: hunk decisions (`ga`, `gr`, `gA`, `gR`, `gu`), review actions (`<CR>`, `gs`, `q`), navigation (`]c`, `[c`), and help (`?`)
