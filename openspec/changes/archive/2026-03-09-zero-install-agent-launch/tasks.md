## 1. AgentDef type and session resolution

- [x] 1.1 Add optional `launch_args_fn` field to `neph.AgentDef` type annotation in `lua/neph/config.lua`
- [x] 1.2 Update `lua/neph/internal/contracts.lua` to allow `launch_args_fn` as a valid optional field on agent definitions
- [x] 1.3 Update `lua/neph/internal/session.lua:open()` to call `launch_args_fn(plugin_root)` when present and append results to `agent_config.args` before building `full_cmd`
- [x] 1.4 Add pcall protection around `launch_args_fn` invocation so errors log a warning but still launch with static args

## 2. Claude agent runtime settings

- [x] 2.1 Rewrite `lua/neph/agents/claude.lua` to use `launch_args_fn` that returns `{"--settings", json}` with absolute path to neph-cli in the hook command
- [x] 2.2 Remove the `tools.merges` field from Claude's agent definition
- [x] 2.3 Verify the generated `--settings` JSON is valid and shell-safe by adding a test

## 3. neph-cli symlink change

- [x] 3.1 Modify `tools.lua:install_async()` to skip the neph-cli symlink during automatic startup install (build only)
- [x] 3.2 Keep symlink creation in `install_universal()` when called from explicit `:NephTools install all` or `:NephTools install neph-cli`
- [x] 3.3 Update `tools.lua:check_version()` to not report neph-cli symlink as stale when symlink is absent but build is current

## 4. Tests

- [x] 4.1 Add test in `tests/agents_spec.lua` that Claude agent definition has `launch_args_fn` and no `tools.merges`
- [x] 4.2 Add test that `launch_args_fn` returns valid JSON containing `hooks.PreToolUse` and an absolute path
- [x] 4.3 Add test in session tests that `launch_args_fn` result is appended to static args
- [x] 4.4 Add test that `launch_args_fn` errors are caught and agent launches with static args only
- [x] 4.5 Update contract tests if `protocol.json` or agent contract validation changes
