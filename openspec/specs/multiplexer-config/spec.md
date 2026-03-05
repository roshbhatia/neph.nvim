## ADDED Requirements

### Requirement: Explicit multiplexer configuration
neph.nvim SHALL accept a `multiplexer` key in its config with values `"native"`, `"wezterm"`, `"tmux"`, `"zellij"`, or `nil`.

#### Scenario: Default nil preserves auto-detection
- **WHEN** `require("neph").setup({})` is called without a `multiplexer` key
- **THEN** the backend is selected via the existing auto-detection logic (SSH → native, WEZTERM_PANE → wezterm, fallback → native)

#### Scenario: Explicit native forces native backend
- **WHEN** `require("neph").setup({ multiplexer = "native" })` is called
- **THEN** the native snacks.nvim backend is used regardless of environment variables

#### Scenario: Explicit wezterm forces wezterm backend
- **WHEN** `require("neph").setup({ multiplexer = "wezterm" })` is called
- **THEN** the wezterm pane backend is used regardless of environment variables

### Requirement: tmux stub backend
neph.nvim SHALL include `lua/neph/backends/tmux.lua` that satisfies the backend interface and emits a warning that tmux support is not yet implemented.

#### Scenario: tmux config emits warning
- **WHEN** `require("neph").setup({ multiplexer = "tmux" })` is called
- **THEN** a `vim.notify` warning is emitted indicating tmux backend is a stub
- **THEN** the native backend is used as fallback

### Requirement: zellij stub backend
neph.nvim SHALL include `lua/neph/backends/zellij.lua` that satisfies the backend interface and emits a warning that zellij support is not yet implemented.

#### Scenario: zellij config emits warning
- **WHEN** `require("neph").setup({ multiplexer = "zellij" })` is called
- **THEN** a `vim.notify` warning is emitted indicating zellij backend is a stub
- **THEN** the native backend is used as fallback
