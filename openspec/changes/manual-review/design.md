## Context

Reviews are currently agent-initiated only — either via RPC `review.open` or the filesystem watcher's automatic detection. Users have no way to manually trigger a review. The existing review infrastructure (engine, UI, queue) is fully reusable; the only missing piece is a user-facing entry point.

## Goals / Non-Goals

**Goals:**
- Provide a `:NephReview [file]` command for manual buffer-vs-disk review
- Expose `require("neph.api").review()` for programmatic use
- Integrate with the existing review queue
- Reuse 100% of existing review engine and UI

**Non-Goals:**
- Git diff mode (buffer vs HEAD) — future enhancement
- Visual selection review — future enhancement
- New review UI features — handled by review-ux-overhaul change

## Decisions

**Post-write mode reuse:** Manual reviews use `mode = "post_write"` because the natural workflow is: agent wrote to disk, user wants to review what changed. Left side = buffer (what user had), right side = disk (what agent wrote). This matches the existing post-write flow exactly.

**Nil result_path and channel_id:** Manual reviews pass `nil` for both. The existing `write_result()` already handles nil gracefully — it skips file writes and RPC notifications. No changes needed to the result delivery path.

**Command interface:** `:NephReview` with optional file path argument. No path = current buffer's file. The command validates: file must exist on disk, buffer must have a name (not scratch), and buffer content must differ from disk (no-op if identical).

**Public API:** `require("neph.api").review(path)` wraps the same logic. Returns `{ok, msg/error}` like other API functions.

**Queue integration:** Manual reviews go through the queue like any other review. If a review is already active, the manual review is queued with a "Review queued" notification. This prevents UI conflicts.

**Request ID format:** `"manual-" .. vim.fn.localtime() .. "-" .. math.random(10000)` — distinguishable from agent-initiated reviews in logs.

## Risks / Trade-offs

- **No-diff guard:** If buffer matches disk, showing a notification and returning is better UX than opening an empty diff tab. Small overhead of reading the file to check.
- **Post-write mode only:** Limits manual reviews to buffer-vs-disk. Git diff mode would need engine changes to read git blobs. Acceptable as v1 — the post-write case covers the primary use case.
