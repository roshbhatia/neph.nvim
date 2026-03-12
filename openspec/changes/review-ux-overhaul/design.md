## Context

The review UI is a vimdiff tab with two scratch buffers (left=current, right=proposed). It uses Neovim's native `:diffthis` for highlighting and scroll sync, and overlays custom signs + keymaps for the hunk-by-hunk decision flow. The engine (`engine.lua`) computes hunks via `vim.diff` with `result_type="indices"`, which returns `{start_a, count_a, start_b, count_b}` tuples. The UI places signs and jumps to hunks based on these ranges.

Current diffopt is inherited from the user's global setting (typically `internal,filler,closeoff,indent-heuristic,inline:char,linematch:40`).

## Goals / Non-Goals

**Goals:**
- Signs perfectly aligned with Neovim's diff highlighting
- Clean visual hierarchy: left pane = decision column + current code, right pane = proposed code with native diff only
- Intuitive keybindings that work immediately without configuration
- Discoverability via `?` help popup
- Consistent, high-quality diff rendering regardless of user's global diffopt
- Minimal visual noise — every element earns its place

**Non-Goals:**
- Moved code detection beyond what `linematch` provides (would need external C library like codediff.nvim)
- Inline layout (single-window unified diff) — the two-pane vimdiff is the right model for review
- Custom diff algorithm implementation — Neovim's internal engine with histogram is excellent

## Decisions

### 1. Sign alignment: use `start_a` directly, no offset

**Choice:** Remove the `-1` offset from sign placement. Place signs on `h.start_a` for the left buffer. For pure insertions (`count_a == 0`), the sign goes on `start_a` which is the line *after which* the insertion happens — this is correct because Neovim shows the filler lines right after that line, so the sign points at where the insertion context is.

**Same for `jump_to_hunk`:** Jump to `h.start_a` instead of `h.start_a - 1`.

**Why the `-1` was wrong:** Neovim's diff highlighting (DiffChange, DiffAdd) starts on `start_a`, not `start_a - 1`. The sign was always one line above the highlighted hunk, creating a visual disconnect.

### 2. Left-side-only signs with simplified semantics

**Choice:** Three sign types, left buffer only:

| Sign | Meaning | Highlight |
|------|---------|-----------|
| `✓` | Accepted (take proposed) | DiagnosticOk (green) |
| `✗` | Rejected (keep current) | DiagnosticError (red) |
| `→` | Current undecided hunk | DiagnosticInfo (blue) |

**Removed:**
- All right-side signs (`right_sign_ids`, right buffer sign placement)
- `💬` (commented/reject-with-reason) — the reason is captured in the envelope and reported to the agent; during review the user just needs to see "rejected". If they want to see the reason they entered, the decision menu shows it.
- Inverse sign logic (left=✗ when accepted was confusing — "I accepted it but my side shows ✗?")

**Why no right-side signs:** The right buffer already has full native diff highlighting (DiffAdd for new lines, DiffText for changed chars, DiffDelete for filler). Adding signs on top just adds noise. The left side is the "control column" — it's where you make decisions.

### 3. Keybindings: `g`-prefix replacing `<localleader>`

**New defaults:**

| Key | Action | Notes |
|-----|--------|-------|
| `ga` | Accept current hunk | Replaces `<localleader>a` |
| `gr` | Reject current hunk | Replaces `<localleader>r`, prompts for optional reason |
| `gA` | Accept all remaining | Replaces `<localleader>A` |
| `gR` | Reject all remaining | Replaces `<localleader>R`, prompts for reason |
| `gu` | Undo decision | Replaces `<localleader>u` |
| `gs` | Submit review | Replaces `<S-CR>` — terminal-safe, no modifier keys |
| `<CR>` | Decision menu | Unchanged |
| `q` | Quit (reject undecided) | Unchanged |
| `?` | Toggle help popup | New |

**Why `g`-prefix:** Vim convention for extended operations (`gq`, `gw`, `gc`, etc.). Two keystrokes with no modifier keys — works in every terminal. `<localleader>` adds an extra layer of indirection and varies per user.

**Why `gs` over `<S-CR>`:** `<S-CR>` doesn't work in many terminals (they send the same code as `<CR>`). `gs` is reliable everywhere, mnemonic ("go submit"), and follows the `g` prefix pattern.

**Override mechanism:** All keys configurable via `config.review_keymaps` — same mechanism as before, just different defaults. The config shape doesn't change.

### 4. Help popup: floating window on `?`

**Choice:** A non-interactive floating window centered in the review tab, showing all keybindings grouped by function. Toggled with `?` — press once to open, press `?` or `q` or `<Esc>` to close. The window is a scratch buffer with `buftype=nofile`, styled with `FloatBorder` and `NormalFloat` highlights.

**Content layout:**
```
┌─ Neph Review ────────────────────────┐
│                                      │
│  ga     Accept hunk                  │
│  gr     Reject hunk (with reason)    │
│  gA     Accept all remaining         │
│  gR     Reject all remaining         │
│  gu     Undo decision                │
│                                      │
│  <CR>   Decision menu                │
│  gs     Submit review                │
│  q      Quit (reject undecided)      │
│                                      │
│  ]c     Next diff hunk               │
│  [c     Previous diff hunk           │
│                                      │
│  ?      Toggle this help             │
│                                      │
└──────────────────────────────────────┘
```

**Why floating:** Modal popups are the standard Neovim pattern for help. A split would disrupt the diff layout. The popup is transparent to the review state — it doesn't change anything, just informs.

### 5. Explicit diffopt per review tab

**Choice:** When opening the review tab, set `diffopt` explicitly on both windows:

```lua
vim.wo[win].diffopt = "internal,filler,closeoff,indent-heuristic,inline:char,linematch:60,algorithm:histogram"
```

Key choices:
- `linematch:60` (bumped from default 40) — agent diffs can produce larger hunks; 60 allows 30-line hunks to be line-matched
- `algorithm:histogram` — produces better diffs for code than the default myers, especially for moved/reindented blocks
- `inline:char` — character-level inline highlighting, the best mode for code review

**Why explicit:** The review is a controlled UX. We don't want a user's `set diffopt=` accidentally disabling filler lines or inline highlighting. The user's global diffopt is restored when the review tab closes (since these are window-local).

Note: `diffopt` is global in Neovim (not window-local). We'll save/restore the user's value around the review tab lifecycle. On tab open, set our review diffopt. On cleanup, restore the original.

### 6. Simplified winbar: left-only, compact

**Choice:** Single winbar on the left window. Format:

```
 POST-WRITE  Hunk 2/5: undecided  ✓1 ✗0 ?4  Review 1/3  ga=accept gr=reject gs=submit ?=help
```

Right window: no winbar. The right window label (PROPOSED / DISK AFTER) moves to the buffer name which already exists (`neph://proposed/filename`).

**Why remove right winbar:** The right winbar was just duplicating the tally. The left winbar has everything the user needs. Removing the right winbar gives more vertical space for code.

### 7. Fillchars for clean filler lines

**Choice:** Set `fillchars` option to use a subtle character for diff filler:

```lua
vim.wo[win].fillchars = "diff:╌"
```

This replaces the default `-` with a lighter dashed line that's less visually dominant. The filler lines (shown by DiffDelete highlight) represent "this content doesn't exist on this side" — they should be visible but not distracting.

## Risks / Trade-offs

- **[`ga` conflicts with Vim's built-in]** → `ga` normally shows ASCII value of char under cursor. This is rarely used during code review, and the keymap is buffer-local so it only overrides in the review tab. Worth the tradeoff for intuitive keybinding.
- **[diffopt is global, not window-local]** → We save/restore around the review lifecycle. Risk: if Neovim crashes mid-review, the user's diffopt stays at our value. Mitigation: our diffopt is a strict superset of the default, so it's not harmful.
- **[Removing right-side signs is a breaking change]** → The `review-dual-signs` spec was designed around dual-side signs. But user feedback says it's noisy — and the inverse semantics (✗ on left for accept) were confusing. The simplification is worth the spec change.
- **[`gs` shadows Vim's sleep command]** → `gs` in normal mode sleeps for [count] seconds. Even more rarely used than `ga`. Buffer-local override in review context is fine.
