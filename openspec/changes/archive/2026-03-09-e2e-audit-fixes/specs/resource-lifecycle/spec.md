## MODIFIED Requirements

### Requirement: Timer cleanup on session teardown

All `vim.loop.new_timer()` instances created by session.lua, file_refresh.lua, or any other module SHALL be stopped and closed when the session is killed or `cleanup_all()` is called.

#### Scenario: Session kill stops timers
- **WHEN** `session.kill(termname)` is called
- **THEN** any retry/polling timers associated with that session are stopped via `timer:stop()` and `timer:close()`
- **AND** no phantom timer callbacks fire after teardown

#### Scenario: File refresh timer stops on plugin teardown
- **WHEN** `cleanup_all()` is called or the plugin is unloaded
- **THEN** the file_refresh polling timer is stopped and closed
- **AND** the checktime autocmd group is cleared

#### Scenario: File refresh double-setup is safe

- **WHEN** `file_refresh.setup()` is called twice without an intervening teardown
- **THEN** the first timer SHALL be stopped and closed before creating the new one
- **AND** no timer leak SHALL occur

#### Scenario: Companion respawn checks agent liveness

- **WHEN** the companion sidecar exits with non-zero code
- **AND** a 2-second deferred respawn is scheduled
- **THEN** the respawn callback SHALL check `vim.g.gemini_active` before restarting
- **AND** if `vim.g.gemini_active` is nil, the respawn SHALL be skipped

#### Scenario: Debounce timers in fs_watcher do not accumulate

- **WHEN** a watched file changes rapidly (multiple events within 200ms)
- **THEN** each new debounce SHALL stop and close the previous debounce timer for that file
- **AND** only one timer per file SHALL exist at any time

## ADDED Requirements

### Requirement: Configurable file_refresh interval

The file_refresh timer interval SHALL be configurable via `neph.Config`.

#### Scenario: Default interval

- **WHEN** no `file_refresh.interval` config is provided
- **THEN** the timer SHALL fire every 1000ms

#### Scenario: Custom interval

- **WHEN** `config.file_refresh.interval` is set to 2000
- **THEN** the timer SHALL fire every 2000ms
