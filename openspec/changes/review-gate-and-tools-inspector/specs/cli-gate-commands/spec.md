## ADDED Requirements

### Requirement: neph gate subcommands control Neovim gate state via RPC
The neph-cli SHALL provide a `gate` command group with subcommands: `hold`, `bypass`, `release`, `status`. Each SHALL resolve `$NVIM_SOCKET_PATH` and execute the corresponding `neph.internal.gate` call via `nvim --server <socket> --remote-expr`. If `NVIM_SOCKET_PATH` is unset or the socket is unreachable, the command SHALL exit with code 1 and print `"neph gate: no Neovim socket — is NVIM_SOCKET_PATH set?"`.

#### Scenario: neph gate hold
- **WHEN** `neph gate hold` is run with a valid `NVIM_SOCKET_PATH`
- **THEN** `gate.set("hold")` is called in Neovim
- **AND** the command exits 0 and prints `"gate: hold"`

#### Scenario: neph gate status
- **WHEN** `neph gate status` is run
- **THEN** the current gate state string is printed to stdout

#### Scenario: No socket available
- **WHEN** `NVIM_SOCKET_PATH` is unset
- **THEN** the command exits 1 with the error message

---

### Requirement: neph gate release drains the held queue
`neph gate release` SHALL call `gate.release()` in Neovim, which drains the hold queue and returns state to `"normal"`.

#### Scenario: Release from hold
- **WHEN** gate is `"hold"` and `neph gate release` is run
- **THEN** `gate.release()` is called, state returns to `"normal"`, queue drains
