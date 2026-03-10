## 1. Review file_path validation

- [x] 1.1 In `review/init.lua:_open_immediate`, add validation after extracting `file_path` from params — return error if not a non-empty string

## 2. Companion timer safety

- [x] 2.1 In `companion.lua:push_context`, wrap `debounce_timer:stop()` in pcall

## 3. Fs_watcher file iteration safety

- [x] 3.1 In `fs_watcher.lua:buffer_differs_from_disk`, wrap `f:lines()` iteration in pcall — on error, close file and return false
