## 1. Review finalize error safety

- [x] 1.1 In `review/ui.lua:do_finalize`, wrap `on_done(session.finalize())` in pcall — on error, log with vim.notify(ERROR)

## 2. Config type validation

- [x] 2.1 In `fs_watcher.lua:start()`, change `config.review or {}` to `type(config.review) == "table" and config.review or {}`
- [x] 2.2 In `review/init.lua:open()`, apply same pattern for `config.review` access
- [x] 2.3 Grep for other `config.X or {}` patterns and fix any that could receive a boolean

## 3. Companion respawn counter reset

- [x] 3.1 In `companion.lua:start_sidecar`, reset `respawn_attempts = 0` at the top when `sidecar_job` is nil (fresh start)

## 4. Snacks timer cleanup

- [x] 4.1 In `snacks.lua`, store ready-detection timer as `td.ready_timer`
- [x] 4.2 In `snacks.lua:kill()`, stop and close `td.ready_timer` if present

## 5. Async handler safety (TypeScript)

- [x] 5.1 In `gate.ts`, wrap notification handler body in try/catch with stderr logging
- [x] 5.2 In `index.ts`, wrap notification handler body in try/catch with stderr logging
- [x] 5.3 In `amp/neph-plugin.ts`, add try/catch to agent.start and agent.end handlers
- [x] 5.4 In `pi/pi.ts`, add try/catch to agent_start, agent_end, tool_call, tool_result handlers

## 6. Gate decision validation

- [x] 6.1 In `gate.ts:handleResult`, validate `json.decision` is a string before using — default to exit 0 if missing

## 7. Signal handler safety

- [x] 7.1 In `companion.ts`, wrap `await cleanup()` in try/catch in SIGTERM and SIGINT handlers

## 8. Diff bridge fixes

- [x] 8.1 In `diff_bridge.ts`, validate `filePath` and `newContent` are strings — return error if not
- [x] 8.2 In `diff_bridge.ts`, use atomic write (writeFileSync to temp + renameSync)
