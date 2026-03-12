## 1. Command Registration

- [x] 1.1 In `lua/neph/init.lua`, add `:NephReview` user command with optional file path argument and completion
- [x] 1.2 The command handler validates: buffer has a file (or arg provided), file exists on disk, buffer differs from disk
- [x] 1.3 On validation failure, show appropriate error notification and return

## 2. Review Entry Point

- [x] 2.1 In `lua/neph/api/review/init.lua`, add `M.open_manual(file_path)` that constructs a review request with `mode = "manual"`, nil result_path and channel_id, and a `"manual-"` prefixed request_id
- [x] 2.2 `open_manual` reads buffer lines as old_lines and disk file as new_lines, then calls `review_queue.enqueue()` or `_open_immediate()`
- [x] 2.3 Handle `mode = "manual"` in `_open_immediate()` — same as post_write but with no result file write on completion

## 3. Public API

- [x] 3.1 In `lua/neph/api.lua`, add `M.review(path)` that calls `require("neph.api.review").open_manual(path or current_buffer_file)`
- [x] 3.2 Return `{ok, msg/error}` consistent with other API functions

## 4. UI Mode Label

- [x] 4.1 In `lua/neph/api/review/ui.lua` `build_winbar()`, add "MANUAL" mode label when `opts.mode == "manual"`

## 5. Tests

- [x] 5.1 Add test for `:NephReview` command validation (no file, nonexistent file, no diff)
- [x] 5.2 Add test for `open_manual()` with mock engine/ui (verify correct params passed)
- [x] 5.3 Add test for manual review result — verify no result file written, no rpcnotify called
