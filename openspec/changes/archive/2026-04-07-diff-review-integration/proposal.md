## Why

Diff review — sending a git diff to the active agent for commentary — currently lives in a separate sysinit utility (`utils/diff_review/`) that was designed to be provider-agnostic and support multiple AI backends (opencode, claude, etc.). With neph as the sole AI integration, that abstraction is vestigial and the implementation is split across three files in two repos. The result is configuration overhead every time you set up a new machine: register the neph provider, wire the plugin dependency, remember where the utility lives.

Moving diff review into neph makes it a first-class feature: zero config, just keymaps.

## What Changes

- **`neph/internal/git.lua`** — Port the pure git utilities (diff_lines, merge_base, in_git_repo) from sysinit into neph as an internal module. This is stable, reusable logic that other neph features (e.g. context enrichment) may eventually use.
- **`neph/api/diff.lua`** — New module implementing `review(scope, opts)` and `picker(scope)`. Sends formatted diff directly to the active agent via `session.ensure_active_and_send`. No provider registry — neph is the provider. Prompt text is configurable via `neph.setup()`.
- **`neph/api.lua`** — Expose `diff_review(scope, opts)` and `diff_picker(scope)` on the public surface.
- **`neph/config.lua`** — Add optional `diff` config key for customising prompts and `branch_fallback`.
- **sysinit cleanup** — Delete `utils/diff_review/` entirely; delete the `diff-review.lua` plugin spec; move `<leader>dr*` keymaps into the existing `neph.lua` spec.

## Capabilities

### New Capabilities

- `diff-review`: Send git diffs (HEAD, staged, branch, file, hunk) to the active agent with a structured prompt. Scopes map cleanly to `<leader>dr*` keymaps.
- `diff-picker`: Open a snacks.nvim git diff picker (browse without sending to agent). Optional — gracefully degrades if snacks is not available.

### Modified Capabilities

- `neph-config`: Gains optional `diff` block for prompt and branch_fallback customisation.

## Impact

- `lua/neph/internal/git.lua` — new file; ported from sysinit
- `lua/neph/api/diff.lua` — new file; diff review + picker orchestration
- `lua/neph/api.lua` — +`diff_review`, +`diff_picker`
- `lua/neph/config.lua` — +`diff` config schema
- `lua/neph/init.lua` — no changes required
- `~/.config/nvim/lua/sysinit/plugins/diff-review.lua` — deleted
- `~/.config/nvim/lua/sysinit/utils/diff_review/` — deleted
- `~/.config/nvim/lua/sysinit/plugins/neph.lua` — +`<leader>dr*` keymaps
