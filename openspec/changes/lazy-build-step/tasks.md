## 1. Build Script

- [x] 1.1 Create `scripts/build.sh` — iterates `tools/neph-cli`, `tools/amp`, `tools/pi`; runs `npm ci && npm run build` in each; exits non-zero with error message if `npm` not found
- [x] 1.2 Make `scripts/build.sh` executable (`chmod +x`) and add shebang `#!/usr/bin/env bash`
- [x] 1.3 After compiling, call `scripts/build.sh` installs `~/.local/bin/neph` symlink (inline, no separate script)
- [x] 1.4 Verify `task build` in `Taskfile.yml` delegates to `scripts/build.sh` (update if needed)

## 2. Lua Build Module

- [x] 2.1 Create `lua/neph/build.lua` with `M.run()` — shells out to `scripts/build.sh` via `vim.system` asynchronously; notifies on start, success, and failure
- [x] 2.2 Add `dist_is_current(root, pkg_dir)` helper to `lua/neph/internal/tools.lua` — compares newest `src/*.ts` mtime vs `dist/index.js` mtime using `vim.uv.fs_stat`

## 3. Neovim Commands & Setup Integration

- [x] 3.1 Register `:NephBuild` command in `lua/neph/init.lua` — calls `require('neph.build').run()`
- [x] 3.2 Demote `setup()` auto-repair notification — keep symlink repair but make it silent (no `vim.notify` on success, only on failure)

## 4. checkhealth

- [x] 4.1 Add `check_build()` section to `lua/neph/health.lua` — reports OK/WARN/ERROR for neph-cli dist staleness using `dist_is_current()`
- [x] 4.2 Update `check_cli()` hint to include `:NephBuild` alongside `:NephInstall`

## 5. Docs & Config

- [x] 5.1 Add `build = 'bash scripts/build.sh'` to `~/.config/nvim/lua/sysinit/plugins/neph.lua` lazy spec
- [x] 5.2 Update `README.md` quick-start snippet to show `build` key with both shell and Lua variants, and a note about Node requirement
- [x] 5.3 Regenerate `doc/neph.txt` if a vimdoc generation step exists (`task docs` or equivalent)
