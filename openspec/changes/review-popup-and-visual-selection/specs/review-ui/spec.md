## ADDED Requirements

### Requirement: Review style is configurable per-agent and globally

The system SHALL expose a `review.style` config option with values `"tab"` (default) and `"popup"`. AgentDef SHALL support an optional `review_style` field that overrides the global default for that agent. When neither is set, the system SHALL default to `"popup"` for agents with `type = "peer"` and `"tab"` for all other agent types.

#### Scenario: Per-agent override beats global config

- **GIVEN** `setup({ review = { style = "tab" } })`
- **AND** the active agent has `review_style = "popup"`
- **WHEN** a pre-write review is opened
- **THEN** the popup UI SHALL be shown, not the vimdiff tab

#### Scenario: Global config beats agent-type fallback

- **GIVEN** `setup({ review = { style = "tab" } })`
- **AND** the active agent is a peer agent with no explicit `review_style`
- **WHEN** a pre-write review is opened
- **THEN** the vimdiff tab SHALL be shown (the global override beats the peer-default)

#### Scenario: Peer agent with no overrides shows popup

- **GIVEN** no `review.style` is set in setup
- **AND** the active agent has `type = "peer"` with no explicit `review_style`
- **WHEN** a pre-write review is opened
- **THEN** the popup UI SHALL be shown

#### Scenario: Non-peer agent with no overrides shows tab

- **GIVEN** no `review.style` is set in setup
- **AND** the active agent has `type = "hook"` (or `"terminal"`) with no explicit `review_style`
- **WHEN** a pre-write review is opened
- **THEN** the vimdiff tab SHALL be shown

### Requirement: Popup review UI exposes accept / reject / view-diff / later

When `review.style = "popup"` resolves, the system SHALL render a small floating window summarising the proposed change (file path, hunk count, +/- line counts, agent name) and accept four single-key inputs:

- `a` → accept the entire proposed change as-is
- `r` → reject the entire proposed change
- `v` → close the popup and open the existing vimdiff tab (granular keymap surface)
- `q` or `<Esc>` → close the popup; the review SHALL remain active in the queue and can be re-opened via the queue UI

#### Scenario: Accept path resolves the review with FILE_SAVED-equivalent envelope

- **GIVEN** the popup is open for a peer-agent pre-write review
- **WHEN** the user presses `a`
- **THEN** the system SHALL fire `params.on_complete({schema="review/v1", decision="accept", content=params.content, hunks={}, reason="popup-accept"})`
- **AND** call `review_queue.on_complete(params.request_id)` to advance the queue
- **AND** close the popup window

#### Scenario: Reject path resolves the review with DIFF_REJECTED-equivalent envelope

- **GIVEN** the popup is open
- **WHEN** the user presses `r`
- **THEN** `params.on_complete` SHALL fire with `{schema="review/v1", decision="reject", content="", hunks={}, reason="popup-reject"}`
- **AND** the queue SHALL advance

#### Scenario: View flips to vimdiff tab without resolving

- **GIVEN** the popup is open
- **WHEN** the user presses `v`
- **THEN** the popup window SHALL close cleanly
- **AND** `require("neph.api.review")._open_immediate(params)` SHALL be called
- **AND** the vimdiff tab SHALL open with all standard review keymaps (`ga gr gA gR gu gs q gL`) available
- **AND** `on_complete` SHALL NOT fire until the user finalises the review in the tab

#### Scenario: Later path leaves the review in the queue

- **GIVEN** the popup is open
- **WHEN** the user presses `q` or `<Esc>`
- **THEN** the popup window SHALL close
- **AND** `on_complete` SHALL NOT fire
- **AND** the review SHALL remain active at the head of the queue
- **AND** the user MAY re-trigger the popup or open the vimdiff tab manually via existing queue interactions

### Requirement: Popup respects gate state

The popup UI SHALL only be reached for `gate = normal` reviews. Bypass and hold paths SHALL short-circuit before the popup is rendered (the gate handling already lives in `review_queue.enqueue` and `review_queue.schedule_open`; this requirement is documenting the contract, not adding new logic).

#### Scenario: Bypass mode never shows the popup

- **GIVEN** `gate = bypass`
- **AND** the active agent has `review_style = "popup"`
- **WHEN** a pre-write review is enqueued
- **THEN** `_bypass_accept` SHALL fire inside the queue
- **AND** `params.on_complete` SHALL fire with `decision = "accept"` immediately
- **AND** the popup SHALL NOT be rendered

#### Scenario: Hold mode never shows the popup

- **GIVEN** `gate = hold`
- **AND** the active agent has `review_style = "popup"`
- **WHEN** a pre-write review is enqueued
- **THEN** the review SHALL be queued silently
- **AND** the popup SHALL NOT be rendered until the gate is released and the queue drains under `gate = normal`

### Requirement: Popup falls back to vim.ui.select when snacks is unavailable

The popup implementation SHALL prefer `Snacks.win` for rendering when `pcall(require, "snacks")` succeeds. When snacks is unavailable, the implementation SHALL fall back to `vim.ui.select({"Accept", "Reject", "View diff", "Later"}, ...)`. Both paths SHALL produce the same `on_complete` envelope shapes and queue-advancement behavior.

#### Scenario: Snacks rendering preferred

- **GIVEN** `pcall(require, "snacks")` returns `true`
- **WHEN** the popup is opened
- **THEN** a `Snacks.win` floating window SHALL be created with `[a]/[r]/[v]/[q]` keymap labels visible

#### Scenario: vim.ui.select fallback when snacks absent

- **GIVEN** `pcall(require, "snacks")` returns `false`
- **WHEN** the popup is opened
- **THEN** `vim.ui.select` SHALL be invoked with the four options
- **AND** the user's selection SHALL map to the same accept/reject/view/later semantics
