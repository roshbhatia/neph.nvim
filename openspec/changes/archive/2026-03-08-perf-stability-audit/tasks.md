## 1. Critical — Blocking Sleep/System Calls

- [x] 1.1 Replace `vim.fn.system("sleep")` in terminal.lua with `vim.defer_fn()` callback
- [x] 1.2 Replace blocking sleep polling loop in wezterm.lua with `vim.loop.new_timer()` + `vim.schedule_wrap()`
- [x] 1.3 Convert blocking `vim.fn.system("wezterm cli send-text ...")` in session.lua to `vim.fn.jobstart()` with on_exit callback
- [x] 1.4 Replace `assert(io.open())` in review/init.lua with pcall + vim.notify error handling

## 2. Moderate — Blocking External Calls

- [x] 2.1 Replace `io.popen("git ...")` in context.lua with `vim.fn.system()` (cached, runs once per cwd)
- [x] 2.2 ~~Convert blocking git calls in placeholders.lua~~ Kept sync — user-triggered cold path, async would require rewriting entire placeholder pipeline
- [x] 2.3 Cache `vim.fn.executable()` results in agents.lua with module-level table

## 3. Resource Lifecycle

- [x] 3.1 Add timer stop/close to session.lua kill and cleanup_all paths
- [x] 3.2 Add `teardown()` function to file_refresh.lua that stops timer and clears autocmd group
- [x] 3.3 Wire file_refresh.teardown() into session cleanup_all

## 4. Safety Checks

- [x] 4.1 Buffer validity checks already present in session.lua send path (`nvim_buf_is_valid`)
- [x] 4.2 Timer callbacks already use `vim.schedule_wrap()`; replaced shell-based `cmd_exists` with `vim.fn.executable()`
- [x] 4.3 No `termopen` call exists — terminal creation handled by `Snacks.terminal.open()` which manages its own errors

## 5. Verification

- [x] 5.1 Run existing test suite to verify no regressions
- [x] 5.2 Manual smoke test: toggle agent, send prompt, review flow — no freezes
