## MODIFIED Requirements

### Requirement: Explicit multiplexer configuration
neph.nvim SHALL accept a `multiplexer` key in its config with values `"snacks"`, `"wezterm"`, `"tmux"`, `"zellij"`. The default SHALL be `"snacks"`. The value `"native"` is no longer valid; existing configs using `"native"` fall through to the snacks backend silently.

#### Scenario: Default snacks backend
- **WHEN** `require("neph").setup({})` is called without a `multiplexer` key
- **THEN** the snacks.nvim (native) backend is used

#### Scenario: Explicit snacks forces snacks backend
- **WHEN** `require("neph").setup({ multiplexer = "snacks" })` is called
- **THEN** the native snacks.nvim backend is used regardless of environment variables

#### Scenario: Explicit wezterm forces wezterm backend
- **WHEN** `require("neph").setup({ multiplexer = "wezterm" })` is called
- **THEN** the wezterm pane backend is used regardless of environment variables

### Requirement: tmux stub backend
neph.nvim SHALL include `lua/neph/internal/backends/tmux.lua` that satisfies the backend interface and emits a warning that tmux support is not yet implemented.

#### Scenario: tmux config emits warning
- **WHEN** `require("neph").setup({ multiplexer = "tmux" })` is called
- **THEN** a `vim.notify` warning is emitted indicating tmux backend is a stub
- **THEN** the native (snacks) backend is used as fallback

### Requirement: zellij stub backend
neph.nvim SHALL include `lua/neph/internal/backends/zellij.lua` that satisfies the backend interface and emits a warning that zellij support is not yet implemented.

#### Scenario: zellij config emits warning
- **WHEN** `require("neph").setup({ multiplexer = "zellij" })` is called
- **THEN** a `vim.notify` warning is emitted indicating zellij backend is a stub
- **THEN** the native (snacks) backend is used as fallback

## REMOVED Requirements

### Requirement: Auto-detect multiplexer backend
**Reason**: Auto-detection via `SSH_CONNECTION` and `WEZTERM_PANE` environment variables adds fragile heuristics. The default `"snacks"` always works; users who want WezTerm must opt in explicitly.
**Migration**: Users who relied on auto-wezterm detection must add `multiplexer = "wezterm"` to their `setup()` call.
