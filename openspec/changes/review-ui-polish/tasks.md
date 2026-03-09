## 1. Buffer Names

- [x] 1.1 Change left buffer name from `[CURRENT HHMMSS] file.ts` to `neph://current/file.ts`
- [x] 1.2 Change right buffer name from `[PROPOSED HHMMSS] file.ts` to `neph://proposed/file.ts`

## 2. Window Options

- [x] 2.1 Set `vim.wo[win].number = true` on both left and right windows in `open_diff_tab`
- [x] 2.2 Set `vim.b[buf].dropbar_disabled = true` on both buffers to suppress dropbar

## 3. Winbar Labels

- [x] 3.1 Add `CURRENT` prefix to left winbar in `build_winbar` (before hunk info)
- [x] 3.2 Ensure right winbar `PROPOSED` label is set in `refresh_ui` (already exists, verified)

## 4. Validation

- [x] 4.1 Run Lua tests — must pass
- [x] 4.2 Run `stylua --check lua/ tests/` — must pass
