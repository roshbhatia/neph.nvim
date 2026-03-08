## 1. Critical — Blocking Sleep/System Calls

- [ ] 1.1 Replace `vim.fn.system("sleep")` in terminal.lua with `vim.defer_fn()` callback
- [ ] 1.2 Replace blocking sleep polling loop in wezterm.lua with `vim.loop.new_timer()` + `vim.schedule_wrap()`
- [ ] 1.3 Convert blocking `vim.fn.system("wezterm cli send-text ...")` in session.lua to `vim.fn.jobstart()` with on_exit callback
- [ ] 1.4 Replace `assert(io.open())` in review/init.lua with pcall + vim.notify error handling

## 2. Moderate — Blocking External Calls

- [ ] 2.1 Convert blocking `io.popen("git ...")` in context.lua to async `vim.fn.jobstart()` with stdout callback
- [ ] 2.2 Convert blocking `vim.fn.system("git ...")` calls in placeholders.lua to async jobstart
- [ ] 2.3 Cache `vim.fn.executable()` results in agents.lua with module-level table

## 3. Resource Lifecycle

- [ ] 3.1 Add timer stop/close to session.lua kill and cleanup_all paths
- [ ] 3.2 Add `teardown()` function to file_refresh.lua that stops timer and clears autocmd group
- [ ] 3.3 Wire file_refresh.teardown() into session cleanup_all

## 4. Safety Checks

- [ ] 4.1 Add buffer/window validity checks in terminal.lua send before chansend
- [ ] 4.2 Add `vim.schedule_wrap()` to all wezterm.lua jobstart callbacks that call Neovim APIs
- [ ] 4.3 Add error handling around `vim.fn.termopen()` in terminal.lua

## 5. Verification

- [ ] 5.1 Run existing test suite to verify no regressions
- [ ] 5.2 Manual smoke test: toggle agent, send prompt, review flow — no freezes
