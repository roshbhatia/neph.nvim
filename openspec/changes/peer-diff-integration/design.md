## Context

The peer-adapter capability (introduced in `frictionless-by-default`) was designed assuming a uniform "monkey-patch the diff handler" pattern would work for both claudecode.nvim and opencode.nvim. In practice the two plugins expose very different surfaces: claudecode runs an MCP coroutine, opencode rebroadcasts SSE events as `User` autocmds. The original design papered over this asymmetry with a single boolean (`override_diff`), and as a result neither integration ever wired up correctly.

This change accepts the asymmetry and designs each side around the natural seam in its host plugin.

## Goals / Non-Goals

**Goals**

- Pre-write review of agent-initiated edits routes through `neph.internal.review_queue` for both claude and opencode peer agents.
- Gate semantics (`normal`/`hold`/`bypass`) work uniformly across both peer agents and existing post-write/manual review paths.
- Implementation is robust to common upstream-plugin changes (we use the most stable seams each plugin offers).
- No new runtime dependencies beyond what the peer plugins already require.

**Non-Goals**

- Replacing the peer plugins' own send/focus/kill plumbing. Those keep their current direct delegations.
- Building a generic "MCP tool override" abstraction. Two peers, two different protocols, two bespoke adapters.
- Re-implementing manual `<leader>jr` review or fs-watcher post-write review. Both remain agent-agnostic and untouched.

## Decisions

### Decision: Hook claudecode at `claudecode.diff.open_diff_blocking`, not `claudecode.tools`

**Why**: `claudecode.tools.tools[name].handler` is the ostensible entry point but it runs inside the MCP server's coroutine wrapper which we'd have to reimplement. `claudecode.diff.open_diff_blocking` is the function the handler actually calls — it's already coroutine-aware (`coroutine.yield` at the bottom, expects `coroutine.resume(co, mcp_result)` from a callback). We monkey-patch one function and inherit the entire blocking-coroutine contract for free.

**Alternative considered**: replace `M.tools.openDiff.handler` with a custom function. Rejected because the handler must be coroutine-callable, and the dispatcher wraps it via `coroutine.create`. Building our own coroutine wouldn't hit the existing `_G.claude_deferred_responses` path that delivers the MCP response asynchronously. Hooking `open_diff_blocking` keeps us inside the existing coroutine state.

**Implementation sketch:**

```lua
-- lua/neph/peers/claudecode.lua
local function install_diff_override()
  if override_installed then return end
  local ok, diff = pcall(require, "claudecode.diff")
  if not ok then return end

  local _original = diff.open_diff_blocking
  diff.open_diff_blocking = function(old_path, new_path, new_contents, tab_name)
    local co, is_main = coroutine.running()
    if not co or is_main then
      error({ code = -32000, message = "openDiff must run in coroutine context" })
    end

    local request_id = ("claudecode:%s:%d"):format(tab_name, vim.uv.hrtime())
    local review_queue = require("neph.internal.review_queue")

    review_queue.enqueue({
      request_id = request_id,
      path = new_path,
      content = new_contents,
      agent = "claude",
      mode = "pre_write",
      on_complete = function(envelope)
        local result
        if envelope.decision == "accept" then
          result = { content = {
            { type = "text", text = "FILE_SAVED" },
            { type = "text", text = envelope.content or new_contents },
          }}
        else
          result = { content = {
            { type = "text", text = "DIFF_REJECTED" },
            { type = "text", text = tab_name },
          }}
        end
        local resume_ok = coroutine.resume(co, result)
        if not resume_ok then
          log.warn("peers.claudecode", "coroutine.resume failed for tab=%s", tab_name)
        end
        local co_key = tostring(co)
        if _G.claude_deferred_responses and _G.claude_deferred_responses[co_key] then
          _G.claude_deferred_responses[co_key](result)
          _G.claude_deferred_responses[co_key] = nil
        end
      end,
    })

    return coroutine.yield()
  end

  override_installed = true
end
```

**Open question**: does `coroutine.resume` need to be `vim.schedule`-wrapped? `on_complete` fires from `review_queue.on_complete` which is called from various places (UI keymaps, fs-watcher callbacks). UI keymaps are in main loop context — safe. fs-watcher callbacks are libuv fast-context — must `vim.schedule`. Test both paths.

### Decision: Hook opencode at the `User OpencodeEvent:permission.asked` autocmd, not the HTTP/SSE stream

**Why**: opencode.nvim already runs the SSE subscription in `lua/opencode/events.lua` and re-emits typed events as `User` autocmds with `data.event` and `data.port`. Listening to that autocmd avoids:

- Discovering the opencode HTTP port via `pgrep "opencode --port"` (fragile, breaks if opencode is launched differently).
- Maintaining a parallel curl SSE subscription that could fall out of sync with opencode.nvim's own connection state.
- Reimplementing connection lifecycle (reconnect, heartbeat, disconnect detection).

The opencode-peer agent already requires opencode.nvim, so its SSE subscription is always running.

**Alternative considered**: keep the existing `lua/neph/internal/opencode_sse.lua` parallel subscription. Rejected — duplicates work opencode.nvim already does, and the field-name mismatch (`metadata.path` vs `metadata.filepath`) suggests the existing code was never tested against a live opencode.

**Implementation sketch:**

```lua
-- inside lua/neph/peers/opencode.lua, called from M.open():
local function install_permission_listener(port_at_open)
  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("NephOpencodePerm", { clear = true }),
    pattern = "OpencodeEvent:permission.asked",
    callback = function(args)
      local event = args.data.event
      local port = args.data.port  -- prefer payload over closure-captured port
      if event.properties.permission ~= "edit" then return end

      local meta = event.properties.metadata or {}
      local file_path = meta.filepath
      local diff_str = meta.diff
      local perm_id = event.properties.id

      if not file_path or not perm_id then
        log.warn("peers.opencode", "permission.asked missing filepath or id; auto-allowing")
        reply_via_server(port, perm_id or 0, "once")
        return
      end

      local proposed = apply_unified_diff(file_path, diff_str)
      if not proposed then
        log.warn("peers.opencode", "patch failed for %s; auto-allowing", file_path)
        reply_via_server(port, perm_id, "once")
        return
      end

      local request_id = ("opencode:%d:%d"):format(perm_id, vim.uv.hrtime())
      require("neph.internal.review_queue").enqueue({
        request_id = request_id,
        path = file_path,
        content = proposed,
        agent = "opencode",
        mode = "pre_write",
        on_complete = function(envelope)
          local reply = envelope.decision == "accept" and "once" or "reject"
          reply_via_server(port, perm_id, reply)
        end,
      })
    end,
    desc = "Neph: route opencode edit permissions through review queue",
  })
end

local function reply_via_server(port, perm_id, reply)
  local ok, server = pcall(require, "opencode.server")
  if ok then
    server.new(port):next(function(s) s:permit(perm_id, reply) end)
  else
    -- last-resort curl fallback
    ...
  end
end
```

### Decision: Auto-disable opencode.nvim's native edit diff via `vim.g.opencode_opts`

**Why**: opencode.nvim's `plugin/events/permissions/edits.lua` listens to the same User autocmd we want to listen to. Without disabling it, both UIs open. The plugin's autocmd guard is `if not opts.enabled or not opts.edits.enabled then return end` — flip the second flag and it cleanly bows out.

**Alternative considered**: clear opencode.nvim's `OpencodeEdits` augroup. Rejected — fragile (relies on group name not changing), invasive, and the `opts.edits.enabled` flag is the public knob the plugin author intended for this purpose.

**Implementation sketch:**

```lua
-- in lua/neph/peers/opencode.lua M.setup() or M.open():
vim.g.opencode_opts = vim.tbl_deep_extend("force",
  vim.g.opencode_opts or {},
  { events = { permissions = { edits = { enabled = false } } } })
```

`tbl_deep_extend("force", ...)` preserves any other user-set keys. Idempotent (running twice has the same effect). Last-write-wins, so users who explicitly want opencode.nvim's UI back can re-set the flag after neph init — though they would lose neph's review for opencode in the process, which is the intended trade.

### Decision: Delete `opencode_sse.lua` + `opencode_permission.lua`, no migration period

**Why**: these modules don't currently work end-to-end (the integration_group that activates them is unset on the peer agent). Removing them is a no-op for any working configuration. Keeping them as dead aliases adds maintenance cost for no benefit.

**Alternative considered**: keep `integration_groups.opencode_sse` as a no-op alias for one release. Rejected — there's no cohort of users this protects (the group has never functionally connected anything).

### Decision: Use `patch(1)` shell-out for opencode's diff application

**Why**: opencode emits unified diff strings, not full content. We need to derive `content` for the review queue. Reimplementing unified-diff application in pure Lua is ~200 lines of edge-case handling. `patch(1)` is on every developer machine. The current code already does this; we keep the approach but improve the failure mode.

**Failure mode change**: instead of silently auto-allowing on patch failure, log at WARN level and auto-allow with a notification (`vim.notify("Neph: could not apply opencode diff for %s — allowing edit", WARN)`). This preserves agent flow but surfaces the failure visibly. Open question: should patch failure auto-reject instead? Auto-allow risks unreviewed writes; auto-reject risks blocking the agent on a recoverable diff format. Defaulting to allow + notify matches the current implicit behavior; we can flip later if surveys show users prefer the safer side.

## Risks / Trade-offs

- **Coroutine safety for claudecode**: `coroutine.resume` from inside `review_queue.on_complete` callbacks. Most paths are main-loop-safe but fs-watcher callbacks run in libuv fast-context. We need `vim.schedule` wrapping in the on_complete callback before `coroutine.resume`, OR a defensive vim.schedule inside `review_queue.on_complete` itself. Pick one and document.
- **Upstream API drift on claudecode**: `claudecode.diff.open_diff_blocking` is technically internal (no `.` prefix in module-name terms but not documented as public). Future claudecode versions could rename or restructure. Mitigation: log a one-time warning when the override fails to install and fall back to native (current code already does this via early-return; we keep that pattern). Accept that breakage will surface as a missing-review symptom users can report.
- **Upstream API drift on opencode**: opencode plugin's `metadata.filepath`/`metadata.diff` field names are inferred from opencode.nvim's own code. If opencode changes the SSE event shape, our adapter breaks the same way opencode.nvim does. We're no more fragile than the host plugin; in practice we share its blast radius.
- **Field-name verification gap**: this design assumes `event.properties.metadata.filepath` and `event.properties.metadata.diff`. The existing (broken) `opencode_permission.lua` uses `metadata.path`. Before merge, verify against opencode source-of-truth (not opencode.nvim's reading) — there's a small chance the Neovim plugin has the field name wrong too.
- **`patch(1)` portability**: BSD patch (macOS) vs GNU patch (Linux) accept slightly different unified-diff dialects. Existing code uses `patch --no-backup-if-mismatch -s -o ...` which works on both. We keep these flags.
- **Hard-removing `opencode_sse` integration group**: any user with that group in their config gets a slightly louder error than necessary. Trade: don't pretend a feature works when it doesn't. Add a note in CHANGELOG and migration guidance.

## Migration Plan

1. Land this change in one PR (small enough to land as a single commit).
2. Update `frictionless-by-default`'s spec deltas to match — that change is in-progress (41/53 tasks). Either:
   - **(a)** finish frictionless-by-default first, then this lands as a fix on top, or
   - **(b)** update frictionless-by-default's `peer-adapter` spec delta to match the new (working) design before either is archived.
   Recommendation: (b), to avoid an archived spec that documents broken behavior.
3. Run `task test:lua` and the existing peer-registry tests; add new tests for the override paths.
4. Manual verification matrix:
   - claude peer + gate=normal + accept → MCP receives `FILE_SAVED`, file written.
   - claude peer + gate=normal + reject → MCP receives `DIFF_REJECTED`, file unchanged.
   - claude peer + gate=bypass → review_queue auto-resolves, MCP receives `FILE_SAVED` immediately, no UI.
   - opencode peer + gate=normal + accept → opencode `permit("once")` posted, file written by opencode.
   - opencode peer + gate=normal + reject → opencode `permit("reject")` posted, file unchanged.
   - opencode peer + gate=bypass → auto-allow, no UI.
   - claudecode.nvim absent → claude-peer agent shows one-time notification, no error spam.
   - opencode.nvim absent → opencode-peer agent shows one-time notification, no error spam.
5. Update CHANGELOG and README sections on peer agents.

## Resolved Questions

### Q1: opencode event payload field names

**Decision**: use `event.properties.metadata.filepath` and `event.properties.metadata.diff`.

**Verification**: opencode.nvim's own `plugin/events/permissions/edits.lua` reads those exact keys (`local diff = event.properties.metadata.diff` and `local filepath = event.properties.metadata.filepath`). Since the User-autocmd payload is the same object opencode.nvim consumes, those are the canonical keys we receive. The existing broken `opencode_permission.lua` reads `metadata.path` — that was a typo/guess and is one of the reasons it never worked. Field names confirmed against `nickjvandyke/opencode.nvim@HEAD` (cloned to /tmp during exploration).

### Q2: patch-failure policy

**Decision**: auto-allow with a WARN log and a `vim.notify(... WARN)` notification.

**Reasoning**:
- We have no diff to display in the review UI when `patch(1)` fails to apply, so there's no meaningful "review" we can offer the user — auto-reject would block the agent on a UI we can't render.
- Auto-allow preserves agent flow; the user sees the visible WARN notification and can investigate (re-run with debug logging, check `patch` availability, etc.).
- If `patch` failures become frequent in practice, we can flip to auto-reject in a follow-up — the WARN notify gives us the signal needed to know.
- For users who want a stricter posture today, `gate=hold` still queues without applying — a patch failure under `hold` will surface the WARN and auto-allow, but the next `permission.asked` from the same session can be reviewed normally.

### Q3: `vim.schedule` wrapping for `coroutine.resume`

**Decision**: always-schedule.

**Reasoning**: `review_queue.on_complete` callbacks fire from a mix of contexts — UI keymaps (main loop, safe), fs-watcher callbacks (libuv fast-context, unsafe for most nvim API calls), and bypass-mode short-circuit (called inline from `enqueue`). Wrapping `coroutine.resume(co, result)` in `vim.schedule(function() ... end)` is one extra event-loop tick in the hot path and removes the entire class of "is this context safe?" bugs. The `_G.claude_deferred_responses` pump is also scheduled inside the same wrapper for consistency.

### Q4 (added during exploration): permission.replied cleanup

**Decision**: yes, listen for `User OpencodeEvent:permission.replied` and cancel the corresponding queue entry by `path` (or by request_id if we track perm_id → request_id mapping).

**Reasoning**: opencode's own TUI also has accept/reject UI. If a user accepts/rejects there, opencode emits `permission.replied` for the perm_id, but our queued review still sits there waiting. Without this listener, the queue can wedge on a review whose underlying permission has already been resolved upstream. Listening for `permission.replied` and canceling the matching queue entry keeps neph's queue in sync with opencode's actual permission state.
