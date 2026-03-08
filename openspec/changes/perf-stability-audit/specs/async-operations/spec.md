## ADDED Requirements

### Requirement: No blocking system calls in hot paths
All code paths triggered by user actions (send, toggle, picker open) SHALL NOT call `vim.fn.system()`, `io.popen()`, or any other blocking function. External process execution SHALL use `vim.fn.jobstart()` with callbacks wrapped in `vim.schedule_wrap()`.

#### Scenario: Terminal send does not block
- **WHEN** `session.send(termname, text)` is called
- **THEN** the Neovim event loop continues processing immediately
- **AND** any external commands (e.g., wezterm CLI) run asynchronously via jobstart

#### Scenario: Git context expansion is non-blocking
- **WHEN** placeholder expansion calls git commands (branch, diff, status)
- **THEN** the commands run via `vim.fn.jobstart()` with on_stdout/on_exit callbacks
- **AND** the expanded text is delivered to the caller via callback, not return value

### Requirement: Sleep-based waits use timers
Any code that waits for a condition (terminal ready, pane created) SHALL use `vim.defer_fn()` or `vim.loop.new_timer()` instead of `vim.fn.system("sleep ...")` or `vim.wait()`.

#### Scenario: Terminal ready wait uses timer
- **WHEN** a terminal is opened and the send path waits for it to be ready
- **THEN** a `vim.defer_fn()` callback fires after the delay
- **AND** the main event loop is not blocked during the wait

#### Scenario: WezTerm pane polling uses timer
- **WHEN** the wezterm backend polls for a pane to appear
- **THEN** it uses `vim.loop.new_timer()` with a polling interval
- **AND** each poll check runs via `vim.schedule_wrap()`

### Requirement: Executable check caching
`vim.fn.executable()` results SHALL be cached for the duration of the Neovim session. The cache SHALL be a module-level table keyed by command name.

#### Scenario: Cached executable check
- **WHEN** `agents.get_all()` is called multiple times
- **THEN** `vim.fn.executable()` is called at most once per agent command
- **AND** subsequent calls return the cached result

### Requirement: Error handling instead of assert on I/O
File I/O operations SHALL NOT use bare `assert()`. They SHALL use `pcall()` or explicit nil checks and report errors via `vim.notify()`.

#### Scenario: Missing file during review
- **WHEN** `review/init.lua` tries to read a file that does not exist
- **THEN** it shows a `vim.notify()` error message
- **AND** the review session continues or cleanly aborts without crashing Neovim

### Requirement: Jobstart callbacks use schedule_wrap
All `vim.fn.jobstart()` callbacks (on_stdout, on_stderr, on_exit) that call Neovim API functions SHALL be wrapped with `vim.schedule_wrap()`.

#### Scenario: WezTerm jobstart callback
- **WHEN** a wezterm CLI command completes via jobstart
- **THEN** the on_exit callback is wrapped with `vim.schedule_wrap()`
- **AND** any vim.notify or buffer operations inside the callback execute safely
