## ADDED Requirements

### Requirement: Continuous context broadcast file

neph SHALL maintain a JSON snapshot of the current editor state at `vim.fn.stdpath("state") .. "/neph/context.json"` (the "broadcast file"), refreshed on cursor movement, window/tab focus changes, and diagnostic updates. The file SHALL be debounced so that rapid event bursts (e.g. typing) generate at most one write per debounce window.

#### Scenario: Broadcast file written on cursor move

- **WHEN** the broadcaster is enabled
- **AND** the user moves the cursor in a normal source buffer
- **AND** the debounce window (default 50ms) elapses
- **THEN** `vim.fn.stdpath("state") .. "/neph/context.json"` SHALL exist
- **AND** SHALL contain a JSON object with at minimum: `ts`, `cwd`, `buffer.uri`, `buffer.cursor`

#### Scenario: Broadcast file updated on window focus change

- **WHEN** the user enters a different window (`BufWinEnter`)
- **AND** the new window holds a normal source buffer
- **THEN** the broadcast file SHALL be rewritten with the new buffer's URI and cursor

#### Scenario: Broadcast file omits non-source buffers

- **WHEN** the user enters a terminal buffer, floating window, or excluded filetype (NvimTree, snacks_terminal, etc.)
- **THEN** the broadcast file SHALL NOT be rewritten
- **AND** the previous snapshot SHALL remain intact (last-source-window semantics)

### Requirement: Broadcast snapshot schema

The broadcast file SHALL conform to the following JSON shape:

```json
{
  "ts": <integer milliseconds since epoch>,
  "session": <string identifier — usually vim.v.servername>,
  "cwd": <string absolute path>,
  "buffer": {
    "uri": <string file:// URI>,
    "language": <string filetype>,
    "cursor": {"line": <integer 0-indexed>, "character": <integer 0-indexed>},
    "selection": null | {"text": <string>, "range": {"start": {...}, "end": {...}}}
  },
  "visible": [<string file:// URI>, ...],
  "diagnostics": {<file:// URI>: [{"severity": <string>, "message": <string>, "range": {...}}, ...]}
}
```

#### Scenario: Snapshot includes selection when in visual mode

- **WHEN** the user enters visual mode and selects three lines
- **AND** a broadcast event fires
- **THEN** `buffer.selection.text` SHALL contain the selected text
- **AND** `buffer.selection.range` SHALL contain the LSP-shaped start/end positions

#### Scenario: Snapshot omits selection in normal mode

- **WHEN** no visual selection is active
- **AND** a broadcast event fires
- **THEN** `buffer.selection` SHALL be `null` (JSON null) or absent

#### Scenario: Visible files reflect open windows

- **WHEN** the user has three split windows showing `foo.lua`, `bar.ts`, `baz.md`
- **AND** a broadcast event fires
- **THEN** `visible` SHALL contain all three URIs
- **AND** SHALL exclude any windows whose buffer is not a source file

### Requirement: Broadcast can be disabled by config

`config.context_broadcast.enable` SHALL default to `true`. When set to `false`, no autocommands SHALL be registered and no file SHALL be written. `config.context_broadcast.debounce_ms` SHALL accept an integer ≥ 10 and default to 50.

#### Scenario: Disabled broadcaster registers no autocommands

- **WHEN** the user calls `setup({ context_broadcast = { enable = false } })`
- **THEN** the broadcaster module SHALL NOT register any autocommands
- **AND** no broadcast file SHALL be created

#### Scenario: Custom debounce honored

- **WHEN** the user calls `setup({ context_broadcast = { debounce_ms = 200 } })`
- **AND** the user moves the cursor rapidly
- **THEN** the broadcast file SHALL be rewritten at most once per 200ms window
