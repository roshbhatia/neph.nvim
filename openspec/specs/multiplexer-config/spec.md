## REMOVED Requirements

### Requirement: Explicit multiplexer configuration
**Reason**: The `multiplexer` string enum is replaced by direct backend injection via the `backend` config key. String-based resolution added indirection without value.
**Migration**: Replace `multiplexer = "snacks"` with `backend = require("neph.backends.snacks")`. Replace `multiplexer = "wezterm"` with `backend = require("neph.backends.wezterm")`.

### Requirement: tmux stub backend
**Reason**: Stub backends that warn and fall back add noise. With explicit injection, if a user doesn't inject a backend, they get a clear error. Tmux support can be added as a real `neph.backends.tmux` module when implemented.
**Migration**: Remove `multiplexer = "tmux"` from config. No replacement until tmux backend is implemented.

### Requirement: zellij stub backend
**Reason**: Same as tmux — stubs that only warn are unnecessary with explicit injection.
**Migration**: Remove `multiplexer = "zellij"` from config. No replacement until zellij backend is implemented.
