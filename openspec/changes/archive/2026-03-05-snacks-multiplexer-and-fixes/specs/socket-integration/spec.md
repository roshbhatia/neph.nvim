## ADDED Requirements

### Requirement: NVIM_SOCKET_PATH forwarded to agent terminals
neph.nvim's native (snacks) backend SHALL inject `NVIM_SOCKET_PATH` from `vim.env.NVIM_SOCKET_PATH` into the environment of every agent terminal it opens, so that tooling running inside those terminals can reach the parent Neovim instance via msgpack-rpc.

#### Scenario: Socket path present in terminal env
- **WHEN** `vim.env.NVIM_SOCKET_PATH` is set in the parent Neovim session
- **THEN** agent terminals opened by the snacks backend have `NVIM_SOCKET_PATH` set to the same value

#### Scenario: Socket path absent — no injection
- **WHEN** `vim.env.NVIM_SOCKET_PATH` is not set
- **THEN** agent terminals open normally without a `NVIM_SOCKET_PATH` entry in their environment

### Requirement: neph.nvim does not create the socket
neph.nvim SHALL NOT call `vim.fn.serverstart()` or set `--listen` on behalf of the user. The socket must be provided externally (e.g. via `nvim --listen /tmp/nvim.sock` or the user's Neovim init configuration).

#### Scenario: Setup with no socket is a no-op for socket features
- **WHEN** `require("neph").setup({})` is called and `vim.env.NVIM_SOCKET_PATH` is absent
- **THEN** setup completes without error and without attempting to create a socket

### Requirement: README documents socket integration
The README SHALL contain a section explaining `NVIM_SOCKET_PATH`, how to enable a persistent socket (`:listen` / `--listen`), and what functionality it unlocks (shim RPC, vimdiff hunk review in pi.ts).

#### Scenario: Socket section present
- **WHEN** the README is read
- **THEN** it contains a section titled "Socket Integration" or similar with instructions for enabling the socket and a description of what it enables
