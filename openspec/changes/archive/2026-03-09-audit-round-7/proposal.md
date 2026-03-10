## Why

Seventh audit round found three minor hardening issues: missing file_path validation at the review API boundary, an unguarded timer stop in the companion debounce, and an unprotected file iteration in the fs_watcher. These are the last edge-case crash vectors identified after six prior audit rounds.

## What Changes

- Validate `params.path` is a non-empty string in `review/init.lua:_open_immediate` before file operations
- Wrap `debounce_timer:stop()` in pcall in `companion.lua:push_context`
- Wrap `f:lines()` iteration in pcall in `fs_watcher.lua:buffer_differs_from_disk`

## Capabilities

### New Capabilities

_(none)_

### Modified Capabilities

- `review-protocol`: Input validation for file_path parameter at review open boundary
- `gemini-context-provider`: Defensive timer stop in companion debounce

## Impact

- `lua/neph/api/review/init.lua` — file_path validation
- `lua/neph/internal/companion.lua` — pcall on timer stop
- `lua/neph/internal/fs_watcher.lua` — pcall on file iteration
