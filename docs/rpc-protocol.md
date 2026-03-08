# Neph RPC Protocol Reference

This document defines the canonical RPC contract between external processes and Neovim.

## Protocol Specification (`protocol.json`)

The protocol version is currently `neph-rpc/v1`.

### Core Methods

| Method | Params | Async? | Description |
|--------|--------|--------|-------------|
| `review.open` | `request_id`, `result_path`, `channel_id`, `path`, `content` | Yes | Opens an interactive diff review. |
| `status.set` | `name`, `value` | No | Sets a `vim.g` global variable. |
| `status.get` | `name` | No | Gets a `vim.g` global variable. |
| `status.unset` | `name` | No | Unsets a `vim.g` global variable. |
| `buffers.check` | (none) | No | Calls `:checktime` in Neovim. |
| `tab.close` | (none) | No | Closes the current tab. |

## Method Details

### `review.open`

**Params:**
- `request_id` (string): Unique UUID for this review session.
- `result_path` (string): Absolute path where the result JSON should be written.
- `channel_id` (number): RPC channel ID to notify upon completion.
- `path` (string): Absolute path to the file being reviewed.
- `content` (string): The proposed new content.

**Flow:**
1. Neovim opens a diff tab immediately.
2. The user reviews hunks interactively.
3. Upon completion, Neovim writes a `ReviewEnvelope` to `result_path`.
4. Neovim fires a `neph:review_done` notification with the `request_id`.

### `status.set`

**Params:**
- `name` (string): The `vim.g` key.
- `value` (any): The value to set (serialized via msgpack).

### `status.get`

**Params:**
- `name` (string): The `vim.g` key to read.

**Returns:** The current value of the variable, or `nil` if not set.

### `status.unset`

**Params:**
- `name` (string): The `vim.g` key to remove.

## Response Format

All RPC calls return a normalized result object:

**Success:**
```json
{ "ok": true, "result": ... }
```

**Failure:**
```json
{
  "ok": false,
  "error": {
    "code": "METHOD_NOT_FOUND" | "INTERNAL",
    "message": "Human readable error"
  }
}
```

## Review Envelope (`ReviewEnvelope`)

The final result of an interactive review session:

```typescript
interface ReviewEnvelope {
  schema: "review/v1";
  decision: "accept" | "reject" | "partial";
  content: string; // The final content (original if rejected, modified if accepted)
  hunks: Array<{
    index: number;
    decision: "accept" | "reject";
    reason?: string;
  }>;
  reason?: string; // Overall reason if rejected or partial
}
```
