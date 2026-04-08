## ADDED Requirements

### Requirement: summary-threshold

The pre-submit summary floating window is only shown when `session.get_total_hunks() >= 3`. For reviews with fewer than 3 hunks, the existing submit menu behavior is unchanged.

### Requirement: summary-display

The summary is a centered floating window (`relative="editor"`, `border="rounded"`) showing one line per hunk:
- `✓ accepted` for accepted hunks
- `✗ rejected: <reason>` for rejected hunks with a reason (reason truncated to 40 chars)
- `✗ rejected` for rejected hunks without a reason
- `? undecided → will reject` for undecided hunks
- A blank separator line
- A footer: `"<CR> Confirm and submit    q Cancel"`

### Requirement: summary-actions

- `<CR>` in the summary: close the summary window and proceed with finalization (call `do_finalize()`)
- `q` / `<Esc>` in the summary: close the summary window without finalizing; user returns to the review

### Requirement: summary-invoked-from-submit

The summary is invoked from the `gs` keymap handler in `start_review`, replacing the direct `do_finalize()` call (when threshold is met). The summary receives a callback to `do_finalize` rather than calling it directly, keeping `do_finalize` scoped correctly.
