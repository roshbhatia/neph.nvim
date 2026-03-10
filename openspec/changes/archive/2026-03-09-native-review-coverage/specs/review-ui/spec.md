## MODIFIED Requirements

### Requirement: Winbar shows current hunk status with tally

- **WHEN** the cursor is on hunk 2 of 5
- **AND** hunk 2 has been accepted, 3 hunks accepted total, 1 rejected, 1 undecided
- **THEN** the winbar displays hunk status, decision tally (✓3 ✗1 ?1), and keymap hints including `<CR>=submit`

- **WHEN** a review is active and 2 reviews are queued
- **THEN** the winbar SHALL additionally display "Review 1/3" to indicate queue position

## ADDED Requirements

### Requirement: Post-write review visual distinction

The review UI SHALL visually distinguish post-write reviews from pre-write reviews.

#### Scenario: Post-write review winbar label

- **WHEN** a post-write review is open (mode = "post_write")
- **THEN** the winbar SHALL display "Post-write Review" instead of "Review"
- **AND** the left buffer label SHALL be "Buffer (before)" and right SHALL be "Disk (after)"

#### Scenario: Pre-write review winbar label

- **WHEN** a pre-write review is open (mode = "pre_write" or default)
- **THEN** the winbar SHALL display "Review" as before
- **AND** the left buffer label SHALL be "Current" and right SHALL be "Proposed"
