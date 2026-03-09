## ADDED Requirements

### Requirement: Signs placed on both left and right buffers

The review UI SHALL place signs on both the left (current) and right (proposed) buffers during review. Signs on the left buffer SHALL use `h.start_a` adjusted for alignment. Signs on the right buffer SHALL use `h.start_b` adjusted for alignment.

#### Scenario: Accepted hunk shows inverse signs

- **WHEN** hunk 1 is accepted
- **THEN** the left buffer shows `neph_reject` (✗) at the hunk's left-side line
- **AND** the right buffer shows `neph_accept` (✓) at the hunk's right-side line

#### Scenario: Rejected hunk without reason shows inverse signs

- **WHEN** hunk 2 is rejected without a reason
- **THEN** the left buffer shows `neph_accept` (✓) at the hunk's left-side line
- **AND** the right buffer shows `neph_reject` (✗) at the hunk's right-side line

#### Scenario: Rejected hunk with reason shows comment on proposed side

- **WHEN** hunk 3 is rejected with reason "wrong approach"
- **THEN** the left buffer shows `neph_accept` (✓) at the hunk's left-side line
- **AND** the right buffer shows `neph_commented` (💬) at the hunk's right-side line

#### Scenario: Current undecided hunk shows arrow on both sides

- **WHEN** the cursor is on hunk 2 and hunk 2 is undecided
- **THEN** the left buffer shows `neph_current` (→) at the hunk's left-side line
- **AND** the right buffer shows `neph_current` (→) at the hunk's right-side line

#### Scenario: Non-current undecided hunk has no signs

- **WHEN** hunk 4 is undecided and the cursor is on hunk 2
- **THEN** neither left nor right buffer has a sign at hunk 4's lines

### Requirement: Right buffer tracks separate sign IDs

The UI state SHALL maintain separate sign ID tracking for the right buffer (`right_sign_ids`). Sign placement and removal on the right buffer SHALL NOT interfere with left buffer signs.

#### Scenario: Independent sign tracking

- **WHEN** hunk 1 is accepted and hunk 2 is rejected
- **THEN** `left_sign_ids` contains entries for hunk 1 and hunk 2 at their `start_a` lines
- **AND** `right_sign_ids` contains entries for hunk 1 and hunk 2 at their `start_b` lines
- **AND** unplacing a left sign does not affect the right sign for the same hunk
