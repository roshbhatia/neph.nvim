## 1. Internal Git Module

- [x] 1.1 Create `lua/neph/internal/git.lua` — port `in_git_repo`, `git_lines`, `merge_base`, `diff_lines` from sysinit verbatim; add module docstring
- [x] 1.2 Add EmmyLua annotations matching existing neph style

## 2. Config Schema

- [x] 2.1 Add `diff` key to `lua/neph/config.lua` with `prompts.review`, `prompts.hunk`, `branch_fallback` defaults
- [x] 2.2 Validate `diff` block in config normalisation (accept nil → apply defaults)

## 3. API Diff Module

- [x] 3.1 Create `lua/neph/api/diff.lua` with `build_message`, `current_hunk_lines`, `resolve_prompt`
- [x] 3.2 Implement `M.review(scope, opts)` — get diff lines → build message → `session.ensure_active_and_send`; notify on empty diff
- [x] 3.3 Implement `M.picker(scope)` — pcall-gated `snacks.picker.git_diff()` with scope-appropriate args
- [x] 3.4 Return `boolean, string|nil` from both public functions for testability

## 4. Public Surface

- [x] 4.1 Add `M.diff_review(scope, opts)` to `lua/neph/api.lua` — thin wrapper with scope validation
- [x] 4.2 Add `M.diff_picker(scope)` to `lua/neph/api.lua` — thin wrapper

## 5. sysinit Wiring

- [x] 5.1 Add `<leader>dr*` keymaps to `~/.config/nvim/lua/sysinit/plugins/neph.lua` (8 keymaps: 3 pickers + 5 reviews)
- [x] 5.2 Delete `~/.config/nvim/lua/sysinit/plugins/diff-review.lua`
- [x] 5.3 Delete `~/.config/nvim/lua/sysinit/utils/diff_review/` directory and all files

## 6. Tests

- [x] 6.1 Create `tests/api/diff_spec.lua`
- [x] 6.2 Test `review("head")` — stub `git.diff_lines`, assert `session.ensure_active_and_send` called with formatted message
- [x] 6.3 Test `review("hunk")` — stub gitsigns hunks; assert correct message sent
- [x] 6.4 Test empty diff — assert notify called, `ensure_active_and_send` not called
- [x] 6.5 Test no active agent — assert graceful (session module notifies, no crash)
- [x] 6.6 Test `git.lua` directly: `diff_lines` returns nil + error for non-git dir
- [x] 6.7 Add `git.lua` and `api/diff.lua` to `tests/minimal_init.lua` rtp if needed (check the file first — they likely don't need extra rtp since they're inside `lua/neph/`)

## 7. Cleanup + Lint

- [x] 7.1 Run `stylua lua/ tests/` — verify no formatting issues (fix any that appear)
- [x] 7.2 Run `luacheck lua/ tests/` — verify no warnings (note: luacheck may be broken in the env; skip with a note if so)
- [x] 7.3 Run full test suite: `nvim --headless --cmd 'set rtp+=.' --cmd "set rtp+=${PLENARY_PATH:-~/.local/share/nvim/lazy/plenary.nvim}" -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" -c 'qa!'` — verify no regressions
- [ ] 7.4 Sync neph.nvim to lazy.nvim managed copy with `/neph-sync-local`
