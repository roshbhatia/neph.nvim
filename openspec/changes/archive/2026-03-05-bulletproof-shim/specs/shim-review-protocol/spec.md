# Shim Review Protocol

Non-blocking vimdiff review protocol that avoids calling interactive Lua inside an RPC call. The shim opens a diff tab via `exec_lua` (returns immediately), then waits for a pynvim notification fired by the user's keymap decision.

## Capability

**shim-review-protocol** — Non-blocking review architecture using temp files, pynvim notifications, and ReviewEnvelope JSON schema.

## Rationale

The old `preview` command called `vim.fn.getcharstr()` inside `nvim_exec_lua`, which blocks the RPC call until the user presses a key. This deadlocks when the shim runs as a subprocess inside a Neovim `:terminal` buffer, because Neovim's terminal mode owns stdin and cannot route keypresses to both the terminal process and `getcharstr()` simultaneously.

The new `review` command:
1. Writes proposed content to a temp file (avoids msgpack size limits)
2. Calls `exec_lua` to open a diff tab with buffer-local keymaps (returns immediately — no blocking Lua)
3. Subscribes to `neph_review_done` notification via `pynvim.subscribe()`
4. Waits via `nvim.next_message()` (blocks Python thread, Neovim event loop stays live)
5. Reads ReviewEnvelope JSON from a result temp file written by the keymap
6. Performs buffer verification and emits final envelope to stdout

## ReviewEnvelope Schema

```json
{
  "schema": "review/v1",
  "decision": "accept" | "reject" | "partial",
  "content": "<final content after applying accepted hunks>",
  "hunks": [
    { "index": 1, "decision": "accept", "reason": null },
    { "index": 2, "decision": "reject", "reason": "hunk 2 skipped" }
  ],
  "reason": "<top-level rejection reason or concatenated hunk reasons>",
  "verification_error": "<unified diff if buffer != expected>",
  "verification_skipped": true  // if buffer not loaded
}
```

- `decision: "accept"` — all hunks accepted (or no diffs found)
- `decision: "reject"` — all hunks rejected; `content` is empty
- `decision: "partial"` — some hunks accepted, some rejected; `content` contains partially applied changes

## ADDED Requirements

### Requirement: open_diff.lua non-blocking diff UI

- Non-blocking diff UI
- Opens a new tab with two `nofile` buffers: `[CURRENT]` (editable, left) and `[PROPOSED]` (read-only, right)
- Calls `diffthis` on both, jumps to first hunk via `]c` with wrapscan
- If no diffs exist, auto-accepts and exits immediately
- Buffer-local keymaps on left buffer:
  - `y` — accept current hunk (`diffget`, `diffupdate`, advance to next hunk or finalize)
  - `n` — reject current hunk, prompt for reason via `vim.ui.input`, advance
  - `a` — accept all remaining hunks in a loop
  - `d` / `<Esc>` — reject all remaining, prompt for top-level reason
  - `e` — hand off for manual edit (reject with reason "Manual resolution")
- `finalize()` helper: collects `{decision, content, hunks[], reason}` JSON, writes to `result_path`, calls `vim.rpcnotify(channel_id, "neph_review_done")`, closes diff tab
- State stored in module-local variables (not `vim.g`) to avoid collisions with concurrent reviews

### `tools/core/shim.py`

- `LUA_OPEN_DIFF` — loaded from `tools/core/lua/open_diff.lua` at module init
- `cmd_review(file_path: str, dry_run: bool = False)` — replaces `cmd_preview`
  - Reads proposed content from stdin
  - Dry-run path: if `dry_run or NEPH_DRY_RUN=1 or not (NVIM_SOCKET_PATH or discover_nvim_socket())`, emit accept envelope immediately
  - Live path:
    - Write proposed content to `tempfile.mkstemp()` prop file
    - Create result temp file, unlink it (Lua will create it when done)
    - Call `nvim.subscribe("neph_review_done")`
    - Get `channel_id = nvim.channel_id`
    - Call `nvim.exec_lua(LUA_OPEN_DIFF, orig_path, prop_path, result_path, channel_id)` — returns immediately
    - Loop `nvim.next_message()` until `msg[1] == "neph_review_done"`
    - Read `result_path` JSON, run `verify_buffer`, merge verification keys, emit envelope
    - Clean up temp files in `finally`
- `cmd_preview(file_path: str)` — deprecated alias, prints deprecation warning to stderr, calls `cmd_review`
- `_emit_envelope(envelope: dict)` — drops `None` values, prints JSON via `click.echo`

### `tools/pi/pi.ts`

- `ReviewEnvelope` interface replaces `NvimPreviewResult`:
  - `schema?: string`
  - `decision: "accept" | "reject" | "partial"`
  - `content?: string`
  - `hunks?: HunkResult[]`
  - `reason?: string`
  - `verification_error?: string`
  - `verification_skipped?: boolean`
- `HunkResult` interface: `{ index: number; decision: "accept" | "reject"; reason?: string }`
- `review()` function replaces `preview()`:
  - Calls `shimRun(["review", filePath], content)` (not `["preview", ...]`)
  - Returns `ReviewEnvelope`
- Write tool execute: handle `decision: "partial"` — apply `result.content`, surface notes `["partial accept", result.reason, result.verification_error].filter(Boolean).join(" — ")`
- Edit tool execute: same partial handling

### `tools/core/tests/test_shim.py`

- Class `TestReviewProtocol` with tests:
  - `test_dry_run_flag_auto_accepts` — invoke `cmd_review(..., dry_run=True)`, check envelope
  - `test_dry_run_schema_field_present` — assert `out["schema"] == "review/v1"`
  - `test_no_socket_auto_accepts` — mock `discover_nvim_socket` → `None`, expect accept envelope
  - `test_neph_dry_run_env_auto_accepts` — set `NEPH_DRY_RUN=1`, expect accept envelope
  - `test_preview_alias_warns_and_calls_review` — invoke `cmd_preview`, check stderr for "deprecated"
  - `test_review_cli_dry_run_exits_0` — `CliRunner().invoke(..., ["review", "--dry-run", ...])`, exit 0
  - `test_review_without_socket_exits_0` — mock no socket, invoke `review`, exit 0
- Class `TestLuaScriptDispatch` updated:
  - `test_cmd_review_dry_run_does_not_call_exec_lua` — dry-run path should skip RPC entirely

### `tools/pi/tests/pi.test.ts`

- `describe("review()", ...)` — renamed from `preview()`
- All test assertions updated to check `args[0] === "review"` (not `"preview"`)
- `it("surfaces partial rejection notes for decision:partial", ...)` — mock envelope with `decision: "partial"`, `hunks: [...]`, verify notes surfaced in tool result

## REMOVED Requirements

### Requirement: preview.lua deleted

- Deleted (logic superseded by `open_diff.lua`)

## Delta Headers

**shim-review-protocol**: ADDED (new capability — non-blocking diff + ReviewEnvelope)
