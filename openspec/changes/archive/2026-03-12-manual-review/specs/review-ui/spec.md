## MODIFIED Requirements

### Requirement: Review UI accepts manual-mode reviews

The review UI SHALL handle reviews where `result_path` and `channel_id` are nil. The winbar SHALL show "MANUAL" as the mode label instead of "POST-WRITE" or "CURRENT".

#### Scenario: Manual review winbar

- **GIVEN** a manual review is active
- **THEN** the winbar shows "MANUAL" as the mode label

#### Scenario: Manual review cleanup

- **WHEN** a manual review completes or is quit
- **THEN** cleanup proceeds normally
- **AND** no result file write is attempted
- **AND** no RPC notification is sent
