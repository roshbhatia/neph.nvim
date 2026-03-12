## MODIFIED Requirements

### Requirement: Snacks backend cleanup_all stops ready_timers

`cleanup_all()` SHALL iterate all tracked terminals and stop/close any active `ready_timer` before closing windows.

#### Scenario: Terminal waiting for ready pattern during cleanup

- **GIVEN** a terminal has an active ready_timer
- **WHEN** `cleanup_all()` is called
- **THEN** the ready_timer is stopped and closed
- **AND** the timer callback does not fire after cleanup

### Requirement: Session kill clears pending retry timers

`kill_session()` SHALL clear all pending timers for the killed agent before returning.

#### Scenario: Agent killed with pending retry timer

- **GIVEN** agent "goose" has a pending retry timer
- **WHEN** `kill_session("goose")` is called
- **THEN** the retry timer is stopped
- **AND** the timer callback does not fire after kill

### Requirement: fs_watcher debounce timer cleanup on re-trigger

When a watched file triggers a debounce, if a debounce timer already exists for that filepath, the old timer SHALL be stopped and closed before creating a new one.

#### Scenario: File changes twice within debounce window

- **GIVEN** file.lua is watched with a 200ms debounce
- **WHEN** file.lua changes at T=0
- **AND** file.lua changes again at T=100ms
- **THEN** only one debounce timer is active
- **AND** the callback fires once at T=300ms (100ms + 200ms)

### Requirement: Write error checking in review result

`write_result()` SHALL check the return value of `f:write()` and log an error if the write fails.

#### Scenario: Disk full during result write

- **GIVEN** a review finalizes
- **WHEN** `f:write()` fails
- **THEN** an error is logged with the file path and error message
- **AND** `f:close()` is still called

### Requirement: Falsy config value handling

Config values that evaluate to falsy in Lua (e.g., `0`, `false`) SHALL be distinguishable from absent values. `file_refresh.interval = 0` SHALL set interval to 0, not fall back to the default.

#### Scenario: User sets interval to 0

- **GIVEN** config has `file_refresh = { interval = 0 }`
- **WHEN** file_refresh module reads the interval
- **THEN** interval is 0, not 1000
