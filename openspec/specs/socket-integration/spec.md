## MODIFIED Requirements

### Requirement: NVIM_SOCKET_PATH forwarded to agent terminals
neph.nvim's native (snacks) backend SHALL inject `NVIM_SOCKET_PATH` from `vim.env.NVIM_SOCKET_PATH` into the environment of every agent terminal it opens, so that tooling running inside those terminals can reach the parent Neovim instance via msgpack-rpc.

#### Scenario: Socket path present in terminal env
- **WHEN** `vim.env.NVIM_SOCKET_PATH` is set in the parent Neovim session
- **THEN** agent terminals opened by the snacks backend have `NVIM_SOCKET_PATH` set to the same value

#### Scenario: Socket path absent — no injection
- **WHEN** `vim.env.NVIM_SOCKET_PATH` is not set
- **THEN** agent terminals open normally without a `NVIM_SOCKET_PATH` entry in their environment

### Requirement: neph.nvim does not create the socket
neph.nvim SHALL NOT call `vim.fn.serverstart()` or set `--listen` on behalf of the user. The socket must be provided externally.

#### Scenario: Setup with no socket is a no-op for socket features
- **WHEN** `require("neph").setup({})` is called and `vim.env.NVIM_SOCKET_PATH` is absent
- **THEN** setup completes without error and without attempting to create a socket

### Requirement: README documents socket integration and Lua script location
The README SHALL contain a section explaining `NVIM_SOCKET_PATH` and what it enables. The companion tools table SHALL accurately reference the tools directory structure.

#### Scenario: Socket section present
- **WHEN** the README is read
- **THEN** it contains a "Socket Integration" section with instructions for enabling the socket

#### Scenario: Tools directory reference is accurate
- **WHEN** the README companion tools table is read
- **THEN** directory references SHALL match the actual repository structure
- **AND** stale references to non-existent directories (e.g., `tools/core/lua/`) SHALL be corrected

### Requirement: Timeout applied via socket.setdefaulttimeout before pynvim.attach
`shim.py` SHALL apply the connection timeout by calling
`socket.setdefaulttimeout(timeout)` immediately before `pynvim.attach(...)`,
and SHALL reset it to `None` immediately after the attach call returns.
The default timeout for all commands except `cmd_preview` SHALL be `30.0` seconds.
`cmd_preview` SHALL pass `timeout=None` (no timeout) since it blocks on user input.

#### Scenario: Default 30s timeout set before attach for non-preview commands
- **WHEN** `get_nvim()` is called without an explicit timeout argument
- **THEN** `socket.setdefaulttimeout(30.0)` is called before `pynvim.attach`

#### Scenario: No timeout set for preview command
- **WHEN** `get_nvim(timeout=None)` is called (as in `cmd_preview`)
- **THEN** `socket.setdefaulttimeout(None)` is called before `pynvim.attach`

#### Scenario: Timeout reset after attach
- **WHEN** `get_nvim()` completes successfully
- **THEN** `socket.setdefaulttimeout` is restored (called with `None` after attach returns)
