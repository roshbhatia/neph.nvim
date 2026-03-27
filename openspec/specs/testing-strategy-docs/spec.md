### Requirement: TESTING.md documents the two-tier test strategy

The repository SHALL contain a `TESTING.md` at the root that documents the test strategy for contributors.

#### Scenario: TESTING.md exists and covers unit vs integration distinction

- **WHEN** a contributor reads `TESTING.md`
- **THEN** they SHALL find a table or matrix that maps each module/area to its test tier (unit or integration)
- **AND** the document SHALL explain what each tier stubs vs exercises for real
- **AND** the document SHALL include guidance on when to write a unit test vs an integration test

#### Scenario: TESTING.md covers the review pipeline specifically

- **WHEN** a contributor is adding a test for the review flow
- **THEN** `TESTING.md` SHALL explain that `open_diff_tab` must NOT be stubbed in integration tests
- **AND** SHALL explain that engine session and write_result may be stubbed to control hunk count and capture output
- **AND** SHALL explain the tab teardown pattern required in `after_each`

#### Scenario: TESTING.md covers the "empty tab" class of bugs

- **WHEN** a contributor reads the document
- **THEN** they SHALL find an explanation of why RPC-context vim command bugs require integration tests rather than unit tests
- **AND** SHALL understand that unit tests with stubbed `open_diff_tab` cannot catch these bugs
