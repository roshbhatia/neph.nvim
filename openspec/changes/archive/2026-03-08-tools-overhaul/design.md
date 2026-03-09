## Context

The current `tools.lua` generates a monolithic shell script (`build_install_script`) that creates symlinks, runs npm builds, and is executed via `sh -c`. The exit code of the entire script determines success/failure. Problems:

1. `[ -e '/path' ] && ln -sfn ...` returns exit 1 when source doesn't exist — can kill the whole script
2. npm builds at startup are slow and can fail for many reasons (no npm, no node_modules, network)
3. Zero error context — just "Neph tool install had errors"
4. No manual control — users can't install/uninstall/diagnose individual agents
5. No checkhealth integration for debugging

The agent manifest system (`tools.symlinks`, `tools.merges`, `tools.builds`, `tools.files`) is well-designed. The problem is purely in the executor.

## Goals / Non-Goals

**Goals:**
- Replace shell script generation with pure Lua per-agent operations
- Each agent installs/fails independently — one broken agent doesn't block others
- Actionable per-agent error messages
- `:NephTools` command for manual install/uninstall/reinstall/status
- `checkhealth` integration for diagnosing install state
- JSON unmerge for clean uninstall of hook configurations
- `install <agent>` works even when agent isn't on PATH (explicit override)
- Keep npm build step for neph-cli and pi (don't commit dist/)

**Non-Goals:**
- Changing the agent manifest format (symlinks/merges/builds/files is fine)
- Adding a package manager or download system (like mason.nvim)
- Changing how agents are registered (injection via setup())
- Changing the neph-cli or pi source code

## Decisions

### 1. Pure Lua for symlinks, file creation, and JSON operations

**Decision**: Use `vim.uv.fs_symlink()` for symlinks, `vim.fn.writefile()` for files, and existing `json_merge`/new `json_unmerge` for merges. No shell commands for these operations.

**Rationale**: These are simple filesystem operations that Lua handles natively. Eliminates shell quoting bugs and the all-or-nothing exit code problem.

**Alternative**: Keep shell script but add `|| true` after each command. Rejected — still fragile, still no per-agent error context.

### 2. Keep `vim.fn.jobstart` for npm builds only

**Decision**: npm builds (neph-cli, pi) still use `vim.fn.jobstart` since they require spawning node processes. But each build is a separate job with its own exit handling and error reporting.

**Rationale**: Builds genuinely need a subprocess. But making each build independent means a failing pi build doesn't prevent neph-cli from working.

### 3. Per-agent install functions with result reporting

**Decision**: Core API is:
```lua
M.install_agent(root, agent, opts)    → { ok, agent_name, results[] }
M.uninstall_agent(root, agent, opts)  → { ok, agent_name, results[] }
```

Each `results` entry is `{ op = "symlink"|"merge"|"build"|"file", path, ok, err? }`.

**Rationale**: Structured results enable both the async startup path (log errors) and the `:NephTools` command path (show detailed output) to share the same core logic.

### 4. `:NephTools` command structure

**Decision**: Single command with subcommands and tab completion:
```
:NephTools install [all|<agent>]
:NephTools uninstall [all|<agent>]
:NephTools reinstall [all|<agent>]
:NephTools status [<agent>]
```

- `install all`: installs for all agents on PATH + universal (neph-cli)
- `install <agent>`: installs for specific agent regardless of PATH
- `uninstall`: removes symlinks, unmerges JSON, deletes created files
- `status`: shows install state of all agents

**Rationale**: Follows Neovim convention (`:Lazy`, `:Mason`). Single entry point with completion is discoverable. Explicit agent name bypasses PATH check for "I know what I'm doing" scenarios.

### 5. checkhealth provider at `lua/neph/health.lua`

**Decision**: Implement `require("neph.health").check()` which Neovim discovers automatically for `:checkhealth neph`. Reports:
- neph-cli: binary exists, symlink valid, build artifact exists
- Per-agent: on PATH?, tools manifest present?, symlinks valid?, merges applied?, build artifacts exist?
- Dependencies: node available?, npm available?

**Rationale**: Standard Neovim diagnostic pattern. Users can run `:checkhealth neph` to see exactly what's wrong.

### 6. JSON unmerge for clean uninstall

**Decision**: New `json_unmerge(src_path, dst_path, key)` function that removes entries from dst that match entries in src (by `matcher` + `hooks[1].command` for hooks).

**Rationale**: Merges (claude, gemini settings) are additive. To uninstall cleanly, we need to reverse them. The existing `hook_entry_exists` matching logic is reusable.

### 7. Stamp per-agent instead of global

**Decision**: Stamp file at `~/.local/share/nvim/neph_install_<agent>.stamp`. Each agent has its own stamp. Universal neph-cli has `neph_install_neph-cli.stamp`.

**Rationale**: A global stamp means any change triggers reinstall of everything. Per-agent stamps mean only the changed agent gets reinstalled. Also means a failing agent doesn't prevent other agents from being stamped.

**Alternative**: Keep single stamp. Rejected — the current single stamp is one of the reasons the "had errors" message is annoying (retries everything on every launch).

## Risks / Trade-offs

- **[vim.uv.fs_symlink may behave differently across platforms]** → Test on Linux. macOS/Windows are less critical for this plugin. `ln -sfn` fallback via `os.execute` if needed.
- **[JSON unmerge could remove user-added entries that happen to match]** → The matcher + command pair is specific enough. Document that uninstall removes neph-managed entries only.
- **[Per-agent stamps increase file count in data dir]** → Negligible. At most ~10 stamp files.
- **[npm builds as separate jobs add complexity]** → Each build is independent with its own callback. Simpler than the current monolithic script.
