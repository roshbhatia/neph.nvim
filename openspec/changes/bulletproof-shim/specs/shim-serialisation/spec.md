# Shim Serialisation

ReviewEnvelope JSON schema and consumption by pi.ts tool overrides.

## Capability

**shim-serialisation** — Updated to handle ReviewEnvelope schema with `decision: "partial"` and per-hunk rejection notes.

## Rationale

The previous `NvimPreviewResult` only supported `accept` or `reject` (binary choice). The new `ReviewEnvelope` supports `partial` acceptance where some hunks are applied and others are rejected. This allows the agent to see exactly which changes were accepted and why some were rejected, enabling more intelligent retry strategies.

## MODIFIED Requirements

### Requirement: ReviewEnvelope interface replaces NvimPreviewResult

- `ReviewEnvelope` interface replaces `NvimPreviewResult`:
  - Add `schema?: string` field
  - Change `decision` from `"accept" | "reject"` to `"accept" | "reject" | "partial"`
  - Add `hunks?: HunkResult[]` field
  - Add `verification_error?: string` field
  - Add `verification_skipped?: boolean` field
- Write tool override `.then()` block:
  - Add handling for `decision: "partial"` — apply `result.content` (contains partially applied changes)
  - Collect notes array: `["partial accept", result.reason, result.verification_error].filter(Boolean)`
  - Append notes to tool result: `{ type: "text", text: "Note: " + notes.join(" — ") }`
- Edit tool override `.then()` block:
  - Same partial handling as write tool
  - Still delegates to `createEditTool().execute()` for final disk write (not changed)

### `tools/pi/tests/pi.test.ts`

- Test "surfaces partial rejection notes for decision:partial":
  - Mock `review` returns `{ decision: "partial", content: "ok", hunks: [{index:1, decision:"accept"}, {index:2, decision:"reject", reason:"hunk 2 skipped"}], reason: "hunk 2 skipped" }`
  - Assert tool result includes "partial" or rejection reason in notes

## Delta Headers

**shim-serialisation**: MODIFIED (handle ReviewEnvelope `partial` decision + verification fields)
