## 1. Review UI keymap safety

- [x] 1.1 In `review/ui.lua`, add `if finalized then return end` guard at the top of every keymap callback (decide, accept, reject, accept_all, reject_all, submit, next_hunk, prev_hunk)
- [x] 1.2 In `review/ui.lua`, add `if not vim.api.nvim_win_is_valid(ui_state.left_win) then return end` guard in every keymap that calls `nvim_win_get_cursor(ui_state.left_win)`
- [x] 1.3 In `review/ui.lua` reject keymap, add `if finalized then return end` inside the `vim.ui.input` callback before accessing ui_state

## 2. Gate async handler safety

- [x] 2.1 In `gate.ts`, add `.catch()` to `handleResult()` call in the notification handler (line ~314)
- [x] 2.2 In `gate.ts`, add `.catch()` to `handleResult()` call in the fs.watch callback (line ~324)

## 3. Transport listener cleanup

- [x] 3.1 In `transport.ts:SocketTransport`, track notification listeners and remove them in `close()`

## 4. Pi replaceAll fix

- [x] 4.1 In `pi/pi.ts:102`, change `.replace(oldText, newText)` to `.replaceAll(oldText, newText)`
