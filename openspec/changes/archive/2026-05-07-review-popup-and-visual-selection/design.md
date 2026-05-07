## Context

`peer-diff-integration` (just archived) routed peer-agent pre-write reviews through neph's vimdiff tab. Manual verification + a deeper audit surfaced four follow-on issues that all gate the same workflow:

- Visual-mode keymap callbacks see post-mode-transition state, so `<leader>ja` / `<leader>jc` lose the selection.
- The vimdiff tab is overkill for routine accept/reject; users want a popup.
- **Critical**: with `claudecode terminal.provider = "external"` (the user's chosen UX so claude opens in a wezterm pane), `claudecode.terminal.get_active_terminal_bufnr()` returns nil. Our `M.send` chansend path silently no-ops, breaking `<leader>ja`, `<leader>jf`, `<leader>jc`, `<leader>jv`, and all `<leader>dr*` actions for peer claude.
- Two test files still `require("neph.agents.claude")` — a module deleted in the consolidation. Plenary reports these as ERRORS; our previous filter only checked failures.

All four ship together because they share the same UX-quality motivation and three of them are blocked-on-each-other for end-to-end verification.

## Goals / Non-Goals

**Goals**

- Visual-mode keymap callbacks reliably see the just-completed selection.
- Peer-agent pre-write reviews default to a low-friction popup with inline hunks; full vimdiff still one keypress away.
- All `<leader>j*` and `<leader>dr*` text-injection paths work with peer-claude on the external (wezterm) provider.
- Test suite reports zero errors and zero failures.
- No changes to the gate semantics. Bypass still short-circuits before any UI; hold still queues silently.

**Non-Goals**

- Removing the vimdiff tab UI or its existing keymap surface (`ga/gr/gA/gR/gu/gs/q/gL`). Power users keep them.
- Changing the per-hunk envelope shape, queue contract, or peer-adapter wiring beyond the targeted send/visibility helpers.
- Path-2-style "neph fully owns the wezterm backend for peer claude" rewrite. We use a Path-3 cooperation model: claudecode keeps managing its provider; neph slots in as the function-form `external_terminal_cmd` and owns the pane_id. Cleaner upgrade path to Path 2 later if needed.

## Decisions

### Decision: Selection bounds come from marks, not live mode

**Why**: `vim.fn.mode()` is unreliable in keymap callbacks because nvim transitions out of visual mode before the callback fires. The `'<` and `'>` marks are the canonical record of the most recent visual selection, set automatically by nvim and persisted across mode changes. Reading them directly removes the ordering dependency.

**Implementation sketch:**

```lua
-- lua/neph/api.lua
local function get_visual_marks(buf)
  local from = vim.api.nvim_buf_get_mark(buf, "<")
  local to = vim.api.nvim_buf_get_mark(buf, ">")
  if from[1] == 0 and to[1] == 0 then return nil end
  if from[1] > to[1] or (from[1] == to[1] and from[2] > to[2]) then
    from, to = to, from
  end
  -- visualmode() returns the LAST visual mode used: "v", "V", "<C-V>"
  local kind_map = { v = "char", V = "line", ["\22"] = "block" }
  return { from = from, to = to, kind = kind_map[vim.fn.visualmode()] or "char" }
end

function M.ask()
  local marks = get_visual_marks(vim.api.nvim_get_current_buf())
  local default = marks and "+selection " or "+cursor "
  input_for_active("Ask", default, { selection_marks = marks })
end
```

`input_for_active` passes `selection_marks` through to `input.create_input`, which seeds `context.from_marks(buf, marks)` and feeds it to `placeholders.apply` as the `state` arg. The `+selection` provider already reads `state.range`. No mode check anywhere.

**Alternative considered**: read marks inside `context.get_selection_range` itself. Rejected because that function is also called by `auto-context-broadcast` and the source-window snapshot, which should NOT include "the selection from 30 minutes ago" in their continuous JSON. Keeping the marks-based path scoped to the explicit ask/comment keymap callbacks avoids that pollution.

### Decision: Popup is opt-in via `review.style` and per-agent override; peer agents default to popup

**Why**: Two real preferences exist (low-friction popup; surgical vimdiff). Encoding both as styles with a sensible default for each agent kind (peer = popup, terminal/hook = tab) lets each user fall into the right place without configuring anything.

**Resolution order:**
1. `agent.review_style` (per-agent override)
2. `config.review.style` (global)
3. fall-back default (`"popup"` for peer agents, `"tab"` for everyone else)

```lua
-- lua/neph/api/review/init.lua, in set_open_fn
local style = resolve_review_style(params.agent)
if style == "popup" then
  require("neph.api.review.popup").open(params)
else
  M._open_immediate(params)
end
```

### Decision: Popup renders inline hunks via engine.compute_hunks

**Why**: Showing only `+12 / -3` summary leaves users guessing whether the change is what they wanted. The codebase already has `engine.compute_hunks(old_lines, new_lines)` (pure function, returns `HunkRange[]` via `vim.diff`). Reusing it gives a faithful preview without re-implementing diff logic.

**Layout**:

```
┌──────────────────────────────────────────────────┐
│ ✳ claude → write file                            │
│   path/to/file.lua    +12 / -3   2 hunks         │
│                                                  │
│   @@ -3,1 +3,1 @@                                │
│   - return 42                                    │
│   + return 100                                   │
│                                                  │
│   @@ -8,0 +9,1 @@                                │
│   + new_line()                                   │
│   ── 1 more hunk (scroll: ^d / ^u) ──            │
│                                                  │
│   [a] accept   [r] reject   [v] view full diff   │
│   [q / esc] later                                │
└──────────────────────────────────────────────────┘
```

- Bounded height (~16 lines visible). Beyond that, `<C-d>` / `<C-u>` scroll the buffer.
- `[v]iew` flips to the existing `_open_immediate` vimdiff tab — granular keymaps available.
- `[q] / esc` is "later" (review stays in queue), not "reject". Documented prominently.

### Decision: `q`/`<Esc>` defer to queue; explicit `r` to reject

**Why**: Conflating `<Esc>` with reject is a footgun — if the user dismisses the popup by accident, claude's edit is rejected. "Later" semantics let the user think about it without losing the proposal. We document this clearly in the popup label.

### Decision: Path 3 — neph cooperates with claudecode's external provider, owns the pane_id

The fundamental issue: `terminal.provider = "external"` means claude runs in a wezterm pane outside nvim. The bufnr-based `chansend` doesn't apply. We need a way to send text to that pane.

**Why Path 3 (cooperate) over Path 2 (full ownership)**: Path 2 (neph spawns the wezterm pane via a custom claudecode provider) is technically cleanest but invasive — we'd be reimplementing claudecode's terminal provider machinery. Path 3 (neph slots in as the `external_terminal_cmd` function) is a small surface change that gives us pane_id ownership without owning the provider. Upgrade to Path 2 later if Path 3 hits limitations.

**Implementation sketch:**

```lua
-- lua/neph/peers/claudecode.lua
local pane_id = nil

function M.wezterm_pane_cmd(cmd_string, _env_table)
  local pane_file = vim.fn.tempname() .. ".neph-claude-pane-id"

  -- Cleanup pane on nvim exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("NephClaudecodeWezterm", { clear = true }),
    once = true,
    callback = function()
      if pane_id and pane_id ~= "" then
        vim.fn.system({ "wezterm", "cli", "kill-pane", "--pane-id", pane_id })
      end
      pane_id = nil
    end,
  })

  -- Capture pane_id after spawn (deferred so the redirect has flushed)
  vim.defer_fn(function()
    local f = io.open(pane_file, "r")
    if f then
      pane_id = (f:read("*l") or ""):gsub("%s+", "")
      f:close()
      pcall(os.remove, pane_file)
    end
  end, 200)

  return {
    "sh", "-c",
    string.format(
      "wezterm cli split-pane --right --cwd %s -- sh -c %s > %s",
      vim.fn.shellescape(vim.fn.getcwd()),
      vim.fn.shellescape(cmd_string),
      vim.fn.shellescape(pane_file)
    ),
  }
end

-- M.send dispatches based on pane_id presence
function M.send(_td, text, opts)
  ...
  if pane_id and pane_id ~= "" then
    local payload = opts.submit and (text .. "\r") or text
    vim.fn.system({ "wezterm", "cli", "send-text", "--pane-id", pane_id, "--no-paste", payload })
    return
  end
  -- fall through to existing bufnr-based chansend (snacks/native provider)
  ...
end

function M.is_visible(_td)
  if pane_id and pane_id ~= "" then
    -- wezterm cli list and check the pane exists
    local ok, json = pcall(vim.fn.system, { "wezterm", "cli", "list", "--format", "json" })
    if not ok then return false end
    local panes = vim.json.decode(json)
    for _, p in ipairs(panes or {}) do
      if tostring(p.pane_id) == pane_id then return true end
    end
    return false
  end
  -- fall through
  ...
end

function M.focus(_td)
  if pane_id and pane_id ~= "" then
    vim.fn.system({ "wezterm", "cli", "activate-pane", "--pane-id", pane_id })
    return true
  end
  ...
end

function M.kill(_td)
  if pane_id and pane_id ~= "" then
    vim.fn.system({ "wezterm", "cli", "kill-pane", "--pane-id", pane_id })
    pane_id = nil
  end
  -- Stop MCP server too
  local ok, claudecode = try_require_claudecode()
  if ok and type(claudecode.stop) == "function" then pcall(claudecode.stop) end
end
```

**User config migration:**

```lua
-- ~/.config/nvim/lua/plugins/claudecode.lua
provider_opts = {
  external_terminal_cmd = function(cmd, env)
    return require("neph.peers.claudecode").wezterm_pane_cmd(cmd, env)
  end,
},
```

The 200ms `defer_fn` is a known race-window: text sent within that window before the pane_id is captured falls through to the chansend path (which fails for external) — we accept this since `M.send` is typically called minutes after open, not immediately. If it becomes a real problem, we'd block-read the pane_file with a short timeout instead.

### Decision: Stale test refs use claude-peer

`tests/agents_launch_args_spec.lua` tests `claude.launch_args_fn` (which existed on the old terminal claude). Since claude-peer doesn't have `launch_args_fn`, those test cases need to either:
- Be deleted (the canonical claude is now the peer), or
- Be ported to test some other agent's launch_args_fn (e.g., pi has one).

We'll delete the claude-launch-args test cases (the function no longer exists on claude) and keep the pi-launch-args cases. `tests/e2e/smoke_test.lua` simply switches the require to `claude-peer`.

## Risks / Trade-offs

- **The 200ms pane_id capture race.** Accepted as documented. If it bites, switch to a short-timeout block read with `vim.wait`.
- **`wezterm cli send-text` semantics.** `--no-paste` sends bytes literally; newlines are pressed. For multi-line prompts we send `text + \r`. The claude CLI may handle this differently than chansend (which sends raw bytes to a terminal_job_id). If line-handling differs, we may need to adjust the `--no-paste`/escape strategy.
- **Snacks dependency in popup.** Falls back to `vim.ui.select` cleanly. The user has snacks; documented for those who don't.
- **Two UI surfaces** doubles the test matrix. Mitigated by sharing `on_complete` envelope handling — popup just routes the user's choice into the same code path that the vimdiff tab uses (accept → engine.build_envelope with `decision="accept"`, etc.).
- **`q`/`<Esc>` = "later" is novel** — could surprise users who expect Esc to reject. Document clearly.
- **Marks-based selection per buffer**: if the user has a selection in buffer A, then switches to buffer B and presses `<leader>ja`, the marks are read from buffer B (which may be unset). Correct — matches user intent ("the selection in MY current buffer").
- **`get_active_terminal_bufnr` returning nil under external provider** is a real limitation; the pane_id-based dispatch is our workaround. If claudecode's API changes (e.g., they add a `get_external_pane_id` accessor in a later release), we should switch to that.

## Migration Plan

1. Land in one PR (small enough — ~250 LOC + tests).
2. Run `task test:lua`; fix the two stale-test specs first so the test suite reports zero errors before adding new tests.
3. Manual verification via `wezterm-tui-test`:
   - Visual select a function, `<leader>ja`, type "explain", confirm — neph popup opens with `+selection` expanded; `a` accepts; claude prompt receives the question text via wezterm cli send-text.
   - Same flow with normal mode (no marks) — falls back to `+cursor`.
   - With `claude` (peer) + gate=normal: trigger an edit; popup appears with inline hunks; `a` → MCP FILE_SAVED.
   - Same setup, `r` → MCP DIFF_REJECTED.
   - Same setup, `v` → vimdiff tab; `gA gs` accepts → MCP FILE_SAVED.
   - With gate=bypass: no popup, instant accept (regression check).
   - User config `review = { style = "tab" }` overrides peer default → vimdiff tab.
   - `<leader>jx` mid-session: wezterm pane killed (the M.kill change).
   - `:qa!`: VimLeavePre kills the pane (regression check; logic moved from user config to neph).

## Decision: Async-by-default for all shell-outs; never block the event loop

**Why**: User reports periodic "fully frozen nvim" while using the plugin. The most plausible cause given the codebase is synchronous `vim.fn.system` in autocmd or coroutine-callback contexts — every blocked call freezes the main loop until the subprocess returns. `patch`, `wezterm cli`, and `curl` are all subprocesses we shell out to. None should ever run synchronously from a hot path.

**Audit results from this change's investigation:**

| Site | Sync? | Path |
|---|---|---|
| `lua/neph/peers/opencode.lua:88` (apply_unified_diff: patch) | ❌ sync | autocmd handler → freeze risk |
| `lua/neph/peers/opencode.lua` (reply_via_server curl fallback) | ✅ async (jobstart + detach) | safe |
| Existing wezterm BACKEND (backends/wezterm.lua) | ✅ async | already pattern |
| `lua/neph/api/review/init.lua` (write_result) | mixed | `os.rename` is sync but in-process; `io.open` ditto. Acceptable — no subprocess. |

The opencode patch call is the live freeze risk in shipped code. Our new wezterm cli calls would add several more if naively implemented.

**Implementation rules:**

1. **No `vim.fn.system` in autocmd handlers, libuv callbacks, or coroutine resume points.** Use `vim.fn.jobstart` with `on_stdout`/`on_exit` callbacks and process the result there.
2. **`is_visible` may NOT shell out.** It's called from session.lua synchronously (and frequently). Track state internally; trust it.
3. **Fire-and-forget for cleanup actions** (`kill-pane`, `activate-pane`). We don't need the result; just kick off the job.
4. **For paths that need the result async** (patch'd content, etc.), the calling autocmd returns immediately and the eventual on_exit callback continues the work.

**Implementation sketch** for the patch-in-opencode case:

```lua
local function apply_unified_diff_async(file_path, diff_str, callback)
  -- ... write tmp_orig and tmp_patch files (sync IO is OK; small files) ...
  local stdout_buf, stderr_buf = {}, {}
  vim.fn.jobstart({
    "patch", "--no-backup-if-mismatch", "-s",
    "-o", tmp_out, tmp_orig, tmp_patch,
  }, {
    on_stdout = function(_, data) for _, l in ipairs(data) do table.insert(stdout_buf, l) end end,
    on_stderr = function(_, data) for _, l in ipairs(data) do table.insert(stderr_buf, l) end end,
    on_exit = function(_, code)
      local result = nil
      if code == 0 then
        local fr = io.open(tmp_out, "r")
        if fr then result = fr:read("*all"); fr:close() end
      end
      pcall(os.remove, tmp_orig)
      pcall(os.remove, tmp_patch)
      pcall(os.remove, tmp_out)
      callback(result)
    end,
  })
end

-- caller (autocmd):
apply_unified_diff_async(file_path, diff_str, function(proposed)
  if not proposed then
    log.warn("peers.opencode", "patch failed for %s — auto-allowing", file_path)
    reply_via_server(port, perm_id, "once")
    return
  end
  review_queue.enqueue({ ... })
end)
```

The autocmd handler returns immediately; the patch runs async; the queue enqueue happens from the on_exit callback. Freeze-impossible.

**Diagnostic instrumentation:**

- `NEPH_DEBUG=1` env var (read at setup) makes `log.lua` flush every line to `${stdpath('state')}/neph/debug.log` immediately — no batching, no buffering. Survives `kill -9 nvim` or hard freezes.
- A simple `watchdog.lua` module exposes `wrap(name, fn) → wrapped`; wrapped functions emit a WARN log line if their execution exceeds 200 ms. We wrap the key callbacks (`set_open_fn` body, popup keymap handlers, peer adapter `M.send` / `M.is_visible`). Background lurking; produces a breadcrumb trail when something hangs.

## Resolved Questions

(no open questions — all five decisions are unambiguous)
