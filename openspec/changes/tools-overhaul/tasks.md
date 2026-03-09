## 1. Core install/uninstall operations (pure Lua)

- [x] 1.1 Replace `build_install_script` with pure Lua `install_symlink(src, dst)` using `vim.uv.fs_symlink` with `os.execute("ln -sfn")` fallback
- [x] 1.2 Add `uninstall_symlink(dst)` that removes symlink via `os.remove`
- [x] 1.3 Add `json_unmerge(src_path, dst_path, key)` that removes matching hook entries from dst
- [x] 1.4 Add `uninstall_file(dst)` that removes a created file
- [x] 1.5 Refactor `install_agent(root, agent)` to run symlinks/merges/files in pure Lua, returning per-operation results `{ op, path, ok, err? }`
- [x] 1.6 Add `uninstall_agent(root, agent)` that reverses all operations from the agent's manifest

## 2. Per-agent builds as independent jobs

- [x] 2.1 Extract build logic into `run_build(root, build_spec, callback)` that runs a single `vim.fn.jobstart` per build
- [x] 2.2 Update `install_async()` to run each agent independently with per-agent callbacks
- [x] 2.3 On build failure, report agent name and error context via `vim.notify`

## 3. Per-agent stamp files

- [x] 3.1 Change `stamp_path()` to `stamp_path(agent_name)` returning `~/.local/share/nvim/neph_install_<name>.stamp`
- [x] 3.2 Update `is_up_to_date(root)` to `is_agent_up_to_date(root, agent_name)` checking per-agent stamp
- [x] 3.3 Update `touch_stamp()` to `touch_stamp(agent_name)`
- [x] 3.4 On install success, stamp only the successful agent; on failure, skip that agent's stamp

## 4. Universal neph-cli install

- [x] 4.1 Extract neph-cli install as `install_universal(root, callback)` — handles symlink + build independently of agents
- [x] 4.2 Give neph-cli its own stamp (`neph_install_neph-cli.stamp`)
- [x] 4.3 Add `uninstall_universal(root)` that removes `~/.local/bin/neph` symlink

## 5. NephTools user command

- [x] 5.1 Register `:NephTools` command in `init.lua` with nargs="+" and completion function
- [x] 5.2 Implement completion: first arg completes to `install/uninstall/reinstall/status`, second arg completes to `all` + registered agent names
- [x] 5.3 Implement `install` subcommand: `all` installs PATH-available agents + universal; `<agent>` force-installs regardless of PATH
- [x] 5.4 Implement `uninstall` subcommand: calls `uninstall_agent` + removes stamp
- [x] 5.5 Implement `reinstall` subcommand: uninstall then install, clearing stamp first
- [x] 5.6 Implement `status` subcommand: show per-agent install state with symlink validity, build artifact presence

## 6. checkhealth provider

- [x] 6.1 Create `lua/neph/health.lua` with `M.check()` function
- [x] 6.2 Report neph-cli status: symlink exists and valid, build artifact exists
- [x] 6.3 Report per-agent status: on PATH, tools manifest present, symlinks valid, merges applied, build artifacts exist
- [x] 6.4 Report dependencies: node available, npm available
- [x] 6.5 Use `vim.health.ok()`, `vim.health.warn()`, `vim.health.error()`, `vim.health.info()` appropriately

## 7. Update existing install_async startup path

- [x] 7.1 Rewrite `install_async()` to use new per-agent install functions
- [x] 7.2 Remove `build_install_script()` and the monolithic `sh -c` invocation
- [x] 7.3 Remove `do_post_install()` — merges and files are now part of the per-agent install
- [x] 7.4 Keep `install()` (sync) working for tests by calling same per-agent functions synchronously

## 8. Tests

- [x] 8.1 Update `tools_test.lua` for new install/uninstall API surface
- [x] 8.2 Add test for `json_unmerge`: removes matching entries, preserves non-matching
- [x] 8.3 Add test for `install_symlink` / `uninstall_symlink` round-trip
- [x] 8.4 Add test for per-agent stamp isolation (one agent stamped, another not)
