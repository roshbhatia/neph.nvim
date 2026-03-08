## Architecture

The review UI rewrite replaces the blocking `inputlist` loop with an event-driven keymap system. The review engine's session state machine gains random-access methods. The vimdiff tab stays as-is.

```
┌─ Vimdiff Tab ───────────────────────────────────────┐
│  winbar: [Hunk 2/5: undecided]  ga gr gA gR ]c [c  │
├─────────────────────┬───────────────────────────────┤
│  [CURRENT]          │  [PROPOSED]                   │
│  (left_buf)         │  (right_buf, readonly)        │
│                     │                               │
│  Signs: ✓ ✗ → 󰟶   │                               │
└─────────────────────┴───────────────────────────────┘
         ↓ keymaps ↓
┌─ Session State Machine ────────────────────────────┐
│  decisions[1..n]: nil | "accept" | "reject"        │
│  current_idx: tracks which hunk cursor is near     │
│  accept_at(i), reject_at(i, reason?)               │
│  is_complete(): all decisions non-nil               │
│  finalize(): build envelope from decisions          │
└────────────────────────────────────────────────────┘
```

## Engine Changes (session state machine)

Current session is sequential-only: `accept()`, `reject()`, `accept_all()`, `reject_all()` advance a cursor. Need random-access:

- `decisions` array: `nil` = undecided, `{decision="accept"}`, `{decision="reject", reason=...}`
- `accept_at(idx)`: Set decisions[idx] to accept
- `reject_at(idx, reason?)`: Set decisions[idx] to reject
- `accept_all_remaining()`: Accept all nil decisions
- `reject_all_remaining(reason?)`: Reject all nil decisions
- `is_complete()`: All decisions are non-nil
- `get_decision(idx)`: Return current decision for hunk idx
- `finalize()`: Same as current — apply_decisions + build_envelope
- Keep backward-compatible: old sequential methods can call the new random-access ones

## UI Changes

### Keymap Registration

When `start_review` is called, register buffer-local keymaps on `left_buf`:

| Key | Action | Notes |
|-----|--------|-------|
| `ga` | Accept current hunk | Update sign, move to next undecided |
| `gr` | Reject current hunk | Prompt for reason (vim.fn.input), update sign |
| `gA` | Accept all remaining | Accept all nil decisions, finalize |
| `gR` | Reject all remaining | Prompt for reason, reject all nil, finalize |
| `]c` | Next hunk | Native vim diff jump (already works in vimdiff) |
| `[c` | Previous hunk | Native vim diff jump |
| `q` | Quit/finalize | Reject all undecided, finalize |

### Hunk Tracking

Need to know which hunk the cursor is on. Two approaches:

**Option A**: Use `]c`/`[c` and track position via autocmd on `CursorMoved`.
**Option B**: Map `]c`/`[c` to custom functions that track the index.

Going with **Option A** — let vim's native `]c`/`[c` work naturally, determine current hunk from cursor line position on the left buffer. When user presses `ga`/`gr`, find which hunk contains or is nearest to the cursor line.

```lua
local function find_hunk_at_cursor(hunks, cursor_line)
  -- Find hunk whose old-side range contains cursor_line
  for i, h in ipairs(hunks) do
    if cursor_line >= h.start_a and cursor_line <= h.end_a then
      return i
    end
  end
  -- Fallback: find nearest hunk
  local best, best_dist = 1, math.huge
  for i, h in ipairs(hunks) do
    local dist = math.min(math.abs(cursor_line - h.start_a), math.abs(cursor_line - h.end_a))
    if dist < best_dist then
      best, best_dist = i, dist
    end
  end
  return best
end
```

### Winbar

Update `vim.wo[left_win].winbar` on each action:

```
[Hunk 2/5: undecided]  |  ga=accept  gr=reject  gA=all  gR=reject-all
```

After deciding: `[Hunk 2/5: accepted]` or `[Hunk 2/5: rejected (too verbose)]`

### Sign Updates

Same signs as current (`neph_accept`, `neph_reject`, `neph_current`, `neph_commented`). On each action:
- Place appropriate sign on hunk start line
- Move `neph_current` sign to next undecided hunk (or remove if all decided)

### Finalization

When `is_complete()` returns true (all hunks decided):
- Clean up keymaps
- Call `on_done(envelope)` callback
- Close diff tab

When user presses `q` or closes tab:
- All undecided hunks → reject
- Finalize with reason "User exited review"

## Config Changes

Add to `neph.Config`:

```lua
review_keymaps = {
  accept = "ga",
  reject = "gr",
  accept_all = "gA",
  reject_all = "gR",
  quit = "q",
}
```

These are buffer-local only — no conflict with global mappings.

## Testing Strategy

### Unit Tests (engine)
- Random-access accept/reject at arbitrary indices
- `is_complete()` with mixed nil/decided states
- `finalize()` with partially decided hunks (should reject undecided)
- `accept_all_remaining` / `reject_all_remaining` only affect nil decisions

### Unit Tests (UI - headless safe)
- Keymap registration creates expected buffer-local maps
- `find_hunk_at_cursor` returns correct index for various cursor positions
- Winbar string generation
- Sign placement logic

### E2E Tests
- Open review, verify keymaps exist on buffer
- Simulate accept/reject via direct session calls, verify finalize produces correct envelope
