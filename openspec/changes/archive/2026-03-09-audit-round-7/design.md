## Context

Final hardening pass after six audit rounds. Three minor edge-case crash vectors remain in Lua code.

## Goals / Non-Goals

**Goals:**
- Validate file_path at the review API entry point
- Make companion debounce timer stop crash-safe
- Make fs_watcher file iteration crash-safe

**Non-Goals:**
- Changing review or companion behavior
- Adding new features

## Decisions

1. **file_path validation**: Check `type(file_path) ~= "string" or file_path == ""` early in `_open_immediate`, return `{ok=false, error="..."}`. This catches nil, non-string, and empty string cases before any io.open calls.

2. **Companion timer pcall**: Change `debounce_timer:stop()` to `pcall(debounce_timer.stop, debounce_timer)`. Same pattern used throughout the codebase for timer cleanup.

3. **fs_watcher file iteration pcall**: Wrap the `for line in f:lines()` loop in pcall. If iteration fails (file deleted mid-read), close the file handle and return false (no diff detected).

## Risks / Trade-offs

None — all changes are purely defensive guards with no behavior change in normal operation.
