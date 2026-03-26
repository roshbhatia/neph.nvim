## ADDED Requirements

### Requirement: Gate module owns global review gate state
`neph.internal.gate` SHALL maintain a single global state value from the set `{ "normal", "hold", "bypass" }`. The initial state SHALL be `"normal"`. The module SHALL expose `get()`, `set(state)`, and `release()` functions. `set()` SHALL validate that the provided state is one of the three valid values and error on invalid input.

#### Scenario: Initial state is normal
- **WHEN** the gate module is first required
- **THEN** `gate.get()` returns `"normal"`

#### Scenario: State transitions are validated
- **WHEN** `gate.set("invalid")` is called
- **THEN** an error is raised with a message listing valid states

#### Scenario: State transitions succeed for valid values
- **WHEN** `gate.set("hold")` is called
- **THEN** `gate.get()` returns `"hold"`

---

### Requirement: Hold mode accumulates reviews without opening UI
When gate state is `"hold"`, the review queue SHALL accept new enqueue calls and store items in its FIFO, but SHALL NOT call `open_fn` to open the review UI. A notification SHALL be shown: `"Neph: review held — N pending"` (where N is the queue depth after enqueue).

#### Scenario: Enqueue in hold mode silences UI
- **WHEN** gate state is `"hold"` and a file write triggers `review_queue.enqueue()`
- **THEN** the item is added to the queue
- **AND** `open_fn` is NOT called
- **AND** a notification shows the pending count

#### Scenario: Multiple items accumulate
- **WHEN** gate state is `"hold"` and three file writes occur
- **THEN** `#queue == 3` and no review UI has opened

---

### Requirement: Release drains held queue sequentially
`gate.release()` SHALL set gate state to `"normal"` and trigger the existing queue drain mechanism so held reviews open one by one. If the queue is empty, `release()` SHALL be a no-op with no notification.

#### Scenario: Release with pending items
- **WHEN** gate state is `"hold"` with 2 queued reviews and `gate.release()` is called
- **THEN** gate state becomes `"normal"`
- **AND** the first review opens immediately via `open_fn`
- **AND** the second opens after the first completes

#### Scenario: Release with empty queue
- **WHEN** gate state is `"hold"` with no queued items and `gate.release()` is called
- **THEN** gate state becomes `"normal"` and no notification is shown

---

### Requirement: Bypass mode auto-accepts all hunks without UI
When gate state is `"bypass"`, `review_queue.enqueue()` SHALL immediately finalize the review with an all-accept synthetic envelope by calling `review/init._apply_post_write()` and `on_complete()`, without opening any UI. A `vim.notify` at `WARN` level SHALL fire once per `gate.set("bypass")` call: `"Neph: review bypass enabled — changes will be auto-accepted"`.

#### Scenario: Bypass auto-accepts on enqueue
- **WHEN** gate state is `"bypass"` and `review_queue.enqueue()` is called
- **THEN** `open_fn` is NOT called
- **AND** the review is immediately finalized as accepted
- **AND** `on_complete()` is called

#### Scenario: Bypass notify fires on activation
- **WHEN** `gate.set("bypass")` is called
- **THEN** a WARN-level notification is shown exactly once

---

### Requirement: API exposes gate cycling and explicit state setters
`neph.api` SHALL expose:
- `api.gate()` — cycles `normal → hold → bypass → normal`
- `api.gate_hold()` — sets state to `"hold"`
- `api.gate_bypass()` — sets state to `"bypass"`
- `api.gate_release()` — calls `gate.release()` (drains and sets normal)
- `api.gate_status()` — returns the current gate state string

#### Scenario: Cycle from normal
- **WHEN** gate is `"normal"` and `api.gate()` is called
- **THEN** gate state becomes `"hold"`

#### Scenario: Cycle from hold
- **WHEN** gate is `"hold"` and `api.gate()` is called
- **THEN** `gate.release()` is called (state becomes `"normal"`, queue drains)

#### Scenario: Cycle from bypass
- **WHEN** gate is `"bypass"` and `api.gate()` is called
- **THEN** gate state becomes `"normal"`

---

### Requirement: Statusline renders gate state
`neph.api.status` SHALL include the gate state in its output when state is not `"normal"`. The format SHALL be `[HELD]` or `[BYPASS]` as a distinct token visible alongside the active agent name.

#### Scenario: Normal state is silent
- **WHEN** gate state is `"normal"`
- **THEN** no gate indicator appears in the statusline component

#### Scenario: Hold state is visible
- **WHEN** gate state is `"hold"`
- **THEN** statusline includes `[HELD]`

#### Scenario: Bypass state is visible
- **WHEN** gate state is `"bypass"`
- **THEN** statusline includes `[BYPASS]`
