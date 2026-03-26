## Context

The review pipeline currently fires immediately on every agent file write, with no runtime way to pause or bypass it short of changing `integration_group` in config and restarting. Users running agents in "let it rip" sessions need two distinct modes: accumulating reviews silently until they're ready to work through them (hold), and trusting the agent entirely for a period (bypass). Separately, there is no visibility into whether agent tool integrations (symlinks, json merges, neph-cli binary) are actually installed — the setup() call validates tools manifests but never installs them, and the CLI that installs them has no status surface accessible from inside Neovim.

The neph-cli already communicates back to Neovim via `nvim --server $NVIM_SOCKET_PATH` (used by the review protocol). `NVIM_SOCKET_PATH` is forwarded to every agent session. This existing pattern is the backbone of both features: CLI gate and tools commands are thin RPC clients that drive Neovim state.

## Goals / Non-Goals

**Goals:**
- Global review gate with three runtime states (normal / hold / bypass) controllable from both Neovim API and neph-cli
- Hold mode accumulates reviews silently and drains the existing queue on release
- Bypass mode auto-accepts all hunks without UI
- `neph.internal.gate` owns gate state; `review_queue` and `fs_watcher` consult it
- Per-agent filesystem install status exposed via `tools.status()` in Lua and `neph tools status` in CLI
- `neph tools install|uninstall|preview` trigger filesystem operations and notify Neovim
- Symmetric CLI↔Lua API surface — same operations available from both sides
- Statusline renders current gate state
- Documentation updated: README, LuaDoc, CLI help text

**Non-Goals:**
- Per-agent runtime gate overrides (static `integration_group` config already covers this)
- Persistent gate state across Neovim restarts
- GUI/TUI install wizard (simple buffer with keymaps is enough)
- Automatic install on `setup()` (install remains an explicit user action)

## Decisions

### Decision 1: Gate state lives in `neph.internal.gate`, not in `review_queue`

**Chosen**: New `lua/neph/internal/gate.lua` module owns the state (`"normal" | "hold" | "bypass"`). `review_queue` and `fs_watcher` call `gate.get()` at decision points.

**Alternative**: Gate flag lives directly in `review_queue`. Simpler but conflates two concerns — the queue's job is ordering, not policy. Extracting gate makes it independently testable and reachable from the statusline without requiring review_queue.

**Rationale**: Gate state is cross-cutting (affects fs_watcher enqueue decision, queue drain, statusline). A dedicated module avoids threading a flag through multiple call sites.

---

### Decision 2: CLI commands are RPC wrappers, not standalone state

**Chosen**: `neph gate hold` executes `nvim --server $NVIM_SOCKET_PATH --remote-expr "luaeval('require(\"neph.internal.gate\").set(\"hold\")')"`. The CLI carries no gate state itself.

**Alternative**: CLI writes gate state to a file (~/.local/share/nvim/neph-gate); Neovim watches it. More robust to socket unavailability but introduces file-based IPC complexity.

**Rationale**: Gate state only matters when Neovim is running. If no socket is available, `neph gate` should fail loudly rather than write to a file that Neovim may never read. The existing review protocol already uses this pattern — consistency matters more than edge-case robustness here.

---

### Decision 3: Hold mode pauses queue drain, does not suppress enqueue

**Chosen**: In hold mode, `review_queue` still calls `enqueue()` — items accumulate in the FIFO. The drain loop (the part that calls `open_fn`) checks `gate.get() == "hold"` before popping. On `gate.set("normal")`, drain is triggered immediately.

**Alternative**: fs_watcher skips enqueue entirely in hold mode. Simpler drain logic but loses the ability to "drain on release" — you'd just miss those reviews.

**Rationale**: The whole point of hold is "review later, not never." Accumulating in the queue and draining on release uses machinery that already exists and is already tested.

---

### Decision 4: Bypass auto-accepts via synthetic envelope, not by skipping fs_watcher

**Chosen**: In bypass mode, `review_queue.enqueue()` calls `review/init._apply_post_write()` immediately with a synthetic all-accept envelope, then calls `on_complete()`. No UI opens.

**Alternative**: fs_watcher checks `gate.get() == "bypass"` and simply drops the event. Simpler but leaves buffer vs disk state unresolved — `checktime` would then re-open the file from disk showing no changes, which is confusing.

**Rationale**: Auto-accepting writes the accepted content through the normal post-write path, leaving the filesystem clean. This matches user expectation: "I trusted the agent, take the changes."

---

### Decision 5: `tools.status()` returns a Lua table; CLI formats it for terminal

**Chosen**: `lua/neph/internal/tools.lua` gains `M.status(root, agents)` returning `{ [agent_name] = { installed = bool, pending = [...], missing = [...] } }`. `:NephStatus` uses this table to render a buffer. `neph tools status` calls Neovim via RPC to get the table and formats it for terminal output.

**Alternative**: CLI does filesystem checks independently without calling Neovim. Avoids RPC dependency but duplicates the fingerprinting logic that lives in tools.lua.

**Rationale**: tools.lua already has all the fingerprinting and path resolution logic. Reusing it from CLI via RPC is simpler than duplicating it in TypeScript.

---

### Decision 6: Gate cycling keymap (`<leader>jg`) cycles normal→hold→bypass→normal

**Chosen**: A single `api.gate()` call cycles through states. Separate `api.gate_hold()`, `api.gate_bypass()`, `api.gate_release()` functions available for explicit keymaps or programmatic use.

**Alternative**: Two separate toggles (hold toggle, bypass toggle). Less discoverable for the common case.

**Rationale**: Single keymap is fast. Explicit functions give scripts and config fine-grained control. Both coexist.

## Risks / Trade-offs

**[Risk] Bypass silently discards hunks the user may have wanted to review** → Mitigation: statusline shows `BYPASS` prominently; first `gate.set("bypass")` call triggers a one-time confirm notification ("Review bypass enabled — all changes will be auto-accepted").

**[Risk] Hold queue grows unbounded during a long hold session** → Mitigation: existing `MAX_QUEUE_SIZE = 50` cap already in place; oldest item dropped with notify when exceeded. No change needed.

**[Risk] CLI gate commands fail silently if socket is unavailable** → Mitigation: CLI validates `$NVIM_SOCKET_PATH` before calling; exits with non-zero and prints "Neph: no Neovim socket — is NVIM_SOCKET_PATH set?" if missing or stale.

**[Risk] `tools.status()` filesystem checks are slow for agents with many symlinks** → Mitigation: status is called on-demand (not on every keystroke). Acceptable latency for an inspector view.

**[Risk] RPC call from CLI to get tools status requires running Neovim** → Mitigation: `neph tools status --offline` flag skips the runtime pipeline query and shows only filesystem state.

## Migration Plan

No breaking changes. All new config keys are optional with safe defaults. Gate state defaults to `"normal"` — existing behavior unchanged unless user explicitly toggles. New CLI commands are additive. New Lua functions are additive.

Doc updates land in the same PR as the implementation.

## Open Questions

- Should `neph gate bypass` require a confirmation keypress the first time per-session, or just a notify? (Current leaning: notify only, non-blocking.)
- Should `:NephStatus` be a floating window or a full-width split buffer? (Leaning: floating, like `:Lazy`.)
- Should `neph tools install` run in the background (async jobstart) and notify Neovim on completion, or block the terminal? (Leaning: block the terminal since it's a one-time setup operation, but notify Neovim via RPC when done.)
