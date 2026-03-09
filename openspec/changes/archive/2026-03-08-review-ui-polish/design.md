## Context

The review UI opens a vimdiff tab with two buffers: CURRENT (left, old content) and PROPOSED (right, new content). Currently:
- Buffer names include `[CURRENT ...]` and `[PROPOSED ...]` prefixes
- Right window winbar shows `PROPOSED`
- Left window winbar shows hunk status + keymaps
- No line numbers set
- Dropbar (and similar plugins) override winbar, hiding labels

## Goals / Non-Goals

**Goals:**
- Labels visible regardless of dropbar or similar winbar-overriding plugins
- Line numbers in both diff windows
- Clean buffer names

**Non-Goals:**
- Changing hunk logic, keymaps, or engine behavior
- Custom dropbar integration (just suppress it for review windows)

## Decisions

### 1. Suppress dropbar via window-local variables

Dropbar respects `vim.b.dropbar_disabled = true` (buffer-local) or `vim.w.dropbar_disabled = true` (window-local). Set this on both review windows so dropbar doesn't override our winbar.

**Why not floating windows or virtual text:** Winbar is the natural place for per-window labels in Neovim. Fighting the winbar system adds complexity. Suppressing dropbar is the minimal fix.

### 2. Move CURRENT label into left winbar alongside hunk info

Currently the left winbar shows: `Hunk 2/5: accepted  ga=accept  gr=reject ...`

Change to: `CURRENT  Hunk 2/5: accepted  ga=accept  gr=reject ...`

The right winbar already shows `PROPOSED` — keep that.

### 3. Clean buffer names

Replace `[CURRENT HHMMSS] file.ts` → `neph://current/file.ts`
Replace `[PROPOSED HHMMSS] file.ts` → `neph://proposed/file.ts`

**Why keep timestamps out:** The timestamp was for uniqueness, but neph:// pseudo-URIs are already unique enough. Cleaner statusline appearance.

### 4. Enable line numbers

Set `vim.wo[win].number = true` on both left and right windows after creating them.

### 5. No changes to `ga` behavior

The `ga` (accept current hunk) + auto-finalize-on-complete behavior is correct. When there's only 1 hunk, accepting it completes the review. The improved winbar (showing `Hunk 1/1`) already makes this clear — the user can see there's only one hunk before pressing `ga`.

## Risks / Trade-offs

- **[Risk] Dropbar suppression variable name changes** → Low risk; `dropbar_disabled` is the documented API. Other winbar plugins (barbecue, etc.) may have their own variables — we can't suppress them all. Document the dropbar fix.
- **[Risk] Buffer name change breaks something** → Low risk; buffer names are display-only, no code references them by string match.
