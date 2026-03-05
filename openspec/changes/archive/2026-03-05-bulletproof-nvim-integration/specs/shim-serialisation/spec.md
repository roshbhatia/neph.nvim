## ADDED Requirements

### Requirement: Fire-and-forget shim calls are serialised
In `pi.ts`, all fire-and-forget shim invocations (checktime, set, unset, close-tab, revert) SHALL be appended to a serial promise queue so that each call starts only after the previous one completes. The queue MUST never block the calling async context (it is append-only and does not await).

#### Scenario: Sequential dispatch order preserved
- **WHEN** two fire-and-forget shim calls are enqueued in order A then B
- **THEN** call B does not start until call A has resolved or rejected

#### Scenario: Queue errors do not break subsequent calls
- **WHEN** a queued shim call fails (e.g., nvim socket error)
- **THEN** the error is swallowed and the next queued call still executes

#### Scenario: Interactive preview bypasses the queue
- **WHEN** `preview()` is called directly via `shimRun`
- **THEN** it is NOT enqueued through the fire-and-forget queue, and runs concurrently if needed

### Requirement: close-tab is only called at session shutdown
The `agent_end` lifecycle handler in `pi.ts` SHALL NOT call `shim close-tab`. The `close-tab` command SHALL only be called in the `session_shutdown` handler.

#### Scenario: Tab survives between agent turns
- **WHEN** the agent completes a turn (agent_end fires) with an open tab
- **THEN** `shim close-tab` is NOT called and the tab remains open

#### Scenario: Tab closed at session end
- **WHEN** `session_shutdown` fires
- **THEN** `shim close-tab` IS called exactly once
