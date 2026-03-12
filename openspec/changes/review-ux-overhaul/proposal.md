## Why

The review diff experience has several UX issues that compound into a confusing, noisy interface: signs are placed on the wrong line (off-by-one from `start_a - 1`), signs are redundantly duplicated on both panes, the keybindings use `<localleader>` prefix which is slow and non-discoverable, there's no help popup, and Neovim's powerful native diff features (inline:char, linematch, filler lines) aren't explicitly guaranteed. The review is the highest-stakes interaction in neph — it's where the user decides what code actually lands. It needs to be perfect.

## What Changes

- **Fix sign alignment** — remove the erroneous `-1` offset from sign placement and cursor jump; signs go on `start_a`/`start_b` directly to align with Neovim's diff highlighting
- **Signs on left side only** — remove all right-side sign tracking; the left pane becomes the "decision column" while the right pane stays clean with only native diff highlighting
- **Replace keybindings** — change defaults from `<localleader>a/r/A/R/u` to `ga/gr/gA/gR/gu`; change submit from `<S-CR>` to `gs`; keep `<CR>` for decision menu and `q` for quit. All still overridable via `config.review_keymaps`
- **Add `?` help popup** — floating window showing all keybindings, dismissible with `?` or `q` or `<Esc>`
- **Explicit diffopt per review tab** — set `diffopt` to `internal,filler,closeoff,indent-heuristic,inline:char,linematch:60,algorithm:histogram` in the review tab windows for consistent, high-quality diffs regardless of user's global setting
- **Simplify winbar** — single left-side winbar with mode, hunk position, tally, and compact keymap hints; remove right-side winbar entirely (was just a tally duplicate)
- **Improve sign semantics** — simplify to three states: `✓` (accepted), `✗` (rejected/rejected-with-reason), `→` (current undecided). Drop the `💬` sign for reject-with-reason (the reason is in the envelope, not a visual concern during review). Drop inverse sign logic.
- **Set fillchars for review** — use a clean fill character for deleted lines instead of the default `-`

## Capabilities

### New Capabilities

- `review-help-popup`: Floating help window showing all review keybindings, toggled with `?`

### Modified Capabilities

- `review-ui`: Fix sign alignment, left-side-only signs, explicit diffopt, simplified winbar, fillchars
- `review-dual-signs`: **BREAKING** — replaced by left-side-only signs. Right-side sign tracking removed entirely.
- `review-walkback`: Update keymap references from `<localleader>` to `g`-prefix defaults

## Impact

- `lua/neph/api/review/ui.lua` — major changes: sign logic, keymaps, winbar, diffopt, help popup, fillchars
- `lua/neph/api/review/init.lua` — minor: pass mode/request_id through ui_state (overlaps audit-round-8)
- `lua/neph/config.lua` — update default keymaps in config schema
- `openspec/specs/review-dual-signs/spec.md` — superseded by left-only signs
- `openspec/specs/review-ui/spec.md` — updated keymap defaults, sign semantics
- `openspec/specs/review-walkback/spec.md` — updated keymap references
