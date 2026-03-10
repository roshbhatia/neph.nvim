## 1. Operator precedence fix

- [x] 1.1 In `review/init.lua:_apply_post_write`, change `not envelope.content:sub(-1) == "\n"` to `envelope.content:sub(-1) ~= "\n"`

## 2. String.replace → replaceAll

- [x] 2.1 In `gate.ts:reconstructEdit`, change `.replace(oldStr, newStr)` to `.replaceAll(oldStr, newStr)`
- [x] 2.2 In `opencode/edit.ts`, change `.replace(args.old_str, args.new_str)` to `.replaceAll()`
- [x] 2.3 In `amp/neph-plugin.ts`, change `.replace(oldStr, newStr)` to `.replaceAll()`

## 3. Timer resource leak

- [x] 3.1 In `fs_watcher.lua` debounce callback, call `timer:stop()` and `timer:close()` before setting `debounce_timers[filepath] = nil`

## 4. UI dialog timeout

- [x] 4.1 In `neph-client.ts:uiSelect()`, add 60s timeout that resolves with `undefined` and cleans up pendingRequests
- [x] 4.2 In `neph-client.ts:uiInput()`, add 60s timeout that resolves with `undefined` and cleans up pendingRequests

## 5. fs.watch error handler

- [x] 5.1 In `gate.ts`, add `watcher.on('error', ...)` that logs to stderr
- [x] 5.2 In `index.ts`, add `watcher.on('error', ...)` that logs to stderr

## 6. Engine bounds check

- [x] 6.1 In `review/engine.lua` finalize, clamp `j` loop to `math.min(start_b + count_b - 1, #new_lines)` when building accepted hunk lines

## 7. Server body size limit

- [x] 7.1 In `gemini/server.ts` body-reading loop, track accumulated length and respond 413 if > 1MB

## 8. Dead code removal

- [x] 8.1 Remove unused `unmap_keymaps` function from `review/ui.lua`

## 9. Wezterm job notification

- [x] 9.1 In `session.lua:send()`, add `vim.notify(WARN)` when wezterm send-text `job_id <= 0`

## 10. Tests

- [x] 10.1 Add test for gate.ts `reconstructEdit` replacing all occurrences
- [x] 10.2 Add test for neph-client uiSelect timeout
