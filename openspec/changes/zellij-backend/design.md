# Zellij Backend – Design

## Summary

Add an explicit Zellij backend so agents run in Zellij panes (not Neovim splits). Zellij's CLI lacks pane-ID-based targeting, so we use a FIFO to capture the pane ID from the spawned process, then rely on relative focus (`move-focus right/left`) for send, focus, and kill. The backend requires a session refactor to add optional `backend.send()` and `backend.single_pane_only`.

---

## Problem

Zellij's CLI does not support:

- Returning the new pane ID from `zellij run`
- Sending text to a pane by ID (`write-chars` targets focused pane only)
- Focusing a pane by ID (`move-focus` is relative)
- Killing a pane by ID (`close-pane` closes focused pane only)

We need a workaround that works with today's Zellij.

---

## Solution Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         Zellij Backend Architecture                             │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  1. SPAWN + CAPTURE PANE ID                                                      │
│     ┌──────────────┐     ┌─────────────────────────────────────────────────┐   │
│     │ Create FIFO  │     │ zellij run -d right --cwd X -- sh -c '           │   │
│     │ /tmp/neph-*  │     │   echo $ZELLIJ_PANE_ID > /tmp/neph-*; exec cmd   │   │
│     └──────┬───────┘     └─────────────────────────────────────────────────┘   │
│            │                              │                                     │
│            │     ┌────────────────────────┘                                     │
│            ▼     ▼                                                               │
│     ┌──────────────────┐                                                        │
│     │ cat /tmp/neph-*   │  ← blocks until child writes; captures pane_id         │
│     │ (jobstart)        │                                                        │
│     └──────────────────┘                                                        │
│                                                                                  │
│  2. SEND / FOCUS / KILL (relative focus)                                         │
│     Layout assumption: [Neovim | Agent] — agent is always to the right           │
│     • focus:  move-focus right                                                     │
│     • send:  move-focus right → write-chars "text" → move-focus left              │
│     • kill:  move-focus left → move-focus right → close-pane                     │
│              (ensure we're on agent: left from agent→Neovim, right→agent)          │
│                                                                                  │
│  3. IS_VISIBLE                                                                   │
│     zellij action list-clients → parse output → check if pane_id appears          │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Design Decisions

### 1. FIFO for Pane ID Capture

**Problem:** `zellij run` does not output the new pane ID.

**Solution:** The spawned shell writes `$ZELLIJ_PANE_ID` to a FIFO before `exec`-ing the agent. We run `cat <fifo>` in parallel; when the child writes, we receive the pane ID.

**Flow:**
1. Create FIFO: `mkfifo /tmp/neph-zellij-<uuid>`
2. Start `cat /tmp/neph-zellij-<uuid>` via `jobstart` (blocks on open until writer appears)
3. Start `zellij run -d right --cwd X -- sh -c 'echo "$ZELLIJ_PANE_ID" > /tmp/neph-zellij-<uuid>; exec agent_cmd'`
4. Child runs, writes pane ID to FIFO, closes; `cat` receives it and prints to stdout
5. `on_stdout` callback captures pane ID; clean up FIFO

**Pane ID format:** `ZELLIJ_PANE_ID` is `terminal_N` (e.g. `terminal_3`). Normalize bare numbers to `terminal_N` for `list-clients` matching.

**Async:** Use `vim.fn.jobstart` for both `cat` and `zellij run`. No blocking. Per async-operations spec.

---

### 2. Optional `backend.send(term_data, text, opts)`

**Problem:** `session.lua` hardcodes `wezterm cli send-text` when `td.pane_id` exists. Zellij needs a different send path.

**Solution:** Add optional `backend.send(term_data, text, opts)`. If present, session calls it. Else fall back to current logic (pane_id → wezterm, buf → chansend).

**Refactor:**
```lua
-- session.lua M.send()
if backend.send then
  backend.send(td, text, opts)
  return
end
-- existing pane_id / buf logic
```

**Backends:**
- **wezterm:** Add `send` that runs `wezterm cli send-text --pane-id X` via jobstart (extract from session)
- **zellij:** Add `send` that runs `move-focus right` → `write-chars "..."` → `move-focus left` via jobstart
- **snacks:** No `send` (optional) — existing `td.buf` + chansend path continues to work

---

### 3. `backend.single_pane_only`

**Problem:** With relative focus, we can only target "the pane to the right." Multiple agent panes would require knowing topology (how many moves to reach each). That's complex and fragile.

**Solution:** Zellij backend sets `single_pane_only = true`. Session, when opening a new agent, first kills all other agents if this flag is set.

**Session change:**
```lua
-- session.lua M.open()
if backend.single_pane_only then
  for name, td in pairs(terminals) do
    if name ~= termname and backend.is_visible(td) then
      backend.kill(td)
      terminals[name] = nil
      -- ... cleanup
    end
  end
end
```

**Result:** Only one agent pane at a time. Layout is always `[Neovim | Agent]`. `move-focus right` = our pane.

---

### 4. `ready_pattern` for Zellij

**Problem:** WezTerm polls `get-text`; snacks uses `nvim_buf_attach`. Zellij has no equivalent for reading pane output by ID.

**Options:**
- **dump-screen:** Focus pane, dump-screen to file, focus back, read file. Heavy and racy for polling.
- **Delay:** Set `td.ready = true` after a fixed delay (e.g. 2–3s).

**Decision:** Use a configurable delay. Add `zellij_ready_delay_ms` (default 2000) to backend config. No pattern matching. Document that `ready_pattern` is ignored for Zellij.

---

### 5. Session Targeting

When running inside Zellij, `zellij` without `--session` targets the current session. We require `ZELLIJ` (or `ZELLIJ_SESSION_NAME`) to be set; if not, backend errors at setup.

---

### 6. Async Compliance

All Zellij CLI calls use `vim.fn.jobstart` with `vim.schedule_wrap` on callbacks. No `vim.fn.system` in hot paths. Per async-operations spec.

---

## Backend Interface Additions

| Addition | Type | Purpose |
|----------|------|---------|
| `backend.send(td, text, opts)` | optional function | Send text to terminal; session calls when present |
| `backend.single_pane_only` | optional boolean | If true, session kills other agents before opening |

**Contracts:** `validate_backend` does not require `send` or `single_pane_only`; they are optional.

---

## Zellij Backend Module Layout

```
lua/neph/backends/zellij.lua
├── setup(opts)           -- Check ZELLIJ, store config
├── open(...)            -- FIFO + zellij run, return td with pane_id, backend_id="zellij"
├── focus(td)            -- move-focus right
├── hide(td)             -- move-focus left, move-focus right, close-pane (ensure on agent)
├── is_visible(td)       -- list-clients, parse, check pane_id
├── kill(td)             -- move-focus left, move-focus right, close-pane (ensure on agent)
├── cleanup_all(terms)   -- for each: move-focus right, close-pane (single pane, so one iteration)
├── send(td, text, opts) -- move-focus right, write-chars, move-focus left
└── single_pane_only     -- true
```

**term_data shape:**
```lua
{
  pane_id = "terminal_3",   -- from FIFO
  backend_id = "zellij",    -- for session send dispatch (optional; session uses backend.send)
  cmd = agent_config.cmd,
  cwd = cwd,
  name = termname,
  ready = false,            -- set true after zellij_ready_delay_ms
}
```

---

## Session Refactor Summary

| File | Change |
|------|--------|
| `session.lua` | At start of `M.send`: if `backend.send` then call it and return |
| `session.lua` | At start of `M.open`: if `backend.single_pane_only` then kill other agents |
| `wezterm.lua` | Add `send(td, text, opts)` (extract from session) |
| `contracts.lua` | No change (send/single_pane_only optional) |

---

## Layout Assumption

`zellij run -d right` opens the new pane to the right of the **focused** pane. When we spawn, Neovim has focus, so the agent pane is created immediately to the right of Neovim. Thus `move-focus right` targets our agent—**provided** there are no other panes between Neovim and the agent. If the user has a complex layout (e.g. `[Neovim | FileBrowser | Agent]`), `move-focus right` would focus FileBrowser, not the agent. We document this as a limitation: Zellij backend works best when Neovim is the only pane in the tab, or the agent is immediately to the right of Neovim.

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| User has complex layout (multiple panes to the right) | Document: Zellij backend works best when Neovim is the only pane or agent is immediately to the right |
| FIFO creation fails (e.g. no /tmp) | Use `os.tmpname()` or `vim.fn.tempname()` for path; fallback to `vim.fn.getpid()`-based path |
| `cat` blocks forever if zellij run fails | Add timeout (e.g. 30s); on timeout, treat as failure, clean up FIFO |
| Pane ID format differs across Zellij versions | Normalize: if bare number, use `"terminal_" .. n` |
| `list-clients` output format changes | Parse defensively; if parse fails, assume visible (fail-open) |

---

## Testing Strategy

1. **Unit:** Mock `vim.fn.jobstart`, `vim.fn.system`; assert correct zellij CLI invocations
2. **Contract:** Add zellij to backend contract test (optional methods)
3. **Manual:** Run Neovim inside Zellij, configure zellij backend, open agent, send prompt, verify pane behavior

---

## Out of Scope

- Multiple agent panes in Zellij (single_pane_only)
- `ready_pattern` support for Zellij (delay only)
- Contributing to Zellij upstream (--pane-id, write-chars --pane-id)

---

## Files to Create/Modify

| Action | Path |
|--------|------|
| Create | `lua/neph/backends/zellij.lua` |
| Modify | `lua/neph/internal/session.lua` (send dispatch, single_pane_only) |
| Modify | `lua/neph/backends/wezterm.lua` (add send) |
| Modify | `openspec/specs/backend-submodules/spec.md` (add zellij scenario) |
| Modify | `AGENTS.md` (document zellij backend) |
