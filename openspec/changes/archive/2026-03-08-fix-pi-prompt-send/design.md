## Context

Pi is an extension-type agent. Unlike terminal-only agents (claude, gemini, etc.) where text goes directly to stdin via `chansend`, pi receives prompts through a polling mechanism:

1. Lua sets `vim.g.neph_pending_prompt = text`
2. Pi's extension polls `vim.g.neph_pending_prompt` every 500ms via `neph get`
3. When found, pi clears it and calls `pi.sendUserMessage(prompt)`

The `send_adapter` in `pi.lua` gates on `vim.g.pi_active` — a flag set asynchronously by pi's extension when `session_start` fires. This creates a race: the terminal exists (backend reports it visible) before pi has finished initializing and setting `pi_active`. The adapter returns `false`, the code falls through to raw `chansend`, and pi never sees the prompt.

```
Timeline showing the race:

  session.open()          pi process boots          user sends prompt
       │                        │                         │
       ├── backend.open() ──────┤                         │
       │   terminal visible ✓   │                         │
       │                        ├── load extensions       │
       │                        │                         │
       │                        ├── session_start fires   │
       │                        │   neph set pi_active ──▶│ TOO LATE
       │                        │                         │
       │                        │         send_adapter called
       │                        │         vim.g.pi_active = nil
       │                        │         → returns false
       │                        │         → chansend fallback (BROKEN)
```

## Goals / Non-Goals

**Goals:**
- Prompts sent to pi are reliably delivered regardless of startup timing
- No prompts are silently dropped due to overwrite races on `neph_pending_prompt`
- The fix is contained to pi's adapter and session send logic — no public API changes

**Non-Goals:**
- Generalizing this to all future extension agents (solve for pi now, generalize if a pattern emerges)
- Changing pi's polling architecture to push-based (that's a bigger change)
- Sub-100ms prompt delivery latency (500ms poll is acceptable)

## Decisions

### Decision 1: Retry-wait in send_adapter instead of immediate fail

**Choice:** When `vim.g.pi_active` is not yet set, the send_adapter queues the prompt into `vim.g.neph_pending_prompt` optimistically and returns `true`. Pi will pick it up once it starts polling.

**Why not retry loop in adapter?** The adapter is called synchronously in session.send(). Adding a timer-based retry there would complicate the send path for all agents. Since pi already polls `neph_pending_prompt`, we can just set it — pi will find it whenever it starts polling.

**Why not wait in ensure_active_and_send?** That function already has a retry loop, but it waits for terminal existence, not extension readiness. Adding extension-specific readiness checks there couples the generic send path to pi's internals.

**Tradeoff:** If pi never starts (crashes during init), the prompt sits in `vim.g.neph_pending_prompt` forever. This is acceptable — the user will see pi failed in the terminal and can re-send.

### Decision 2: Remove the pi_active guard entirely from send_adapter

The `vim.g.pi_active` guard was meant to prevent setting `neph_pending_prompt` when pi isn't running. But the send_adapter is only called when a pi terminal exists (session.send checks `terminals[termname]`). If the terminal exists, pi is either starting or running. Setting the prompt var is always safe:

- **Pi still starting:** It will poll and find the prompt once ready
- **Pi running:** Normal path, works as before
- **Pi crashed:** Terminal still shows the crash; user sees the failure

### Decision 3: No prompt queue needed for now

The 500ms poll with `get → unset → sendUserMessage` is adequate for human-initiated prompts. Users don't type two prompts within 500ms. The `polling` flag in pi.ts prevents re-entrant polls. Keep it simple.

## Risks / Trade-offs

- **[Risk] Prompt set before pi polls** → Pi's first poll picks it up. The prompt var persists in `vim.g` until consumed. No loss.
- **[Risk] Pi crashes before consuming prompt** → Prompt sits in `vim.g.neph_pending_prompt`. Mitigated: session.close() for pi should clean up this var.
- **[Risk] Multiple extension agents in future share neph_pending_prompt** → Currently only pi uses this pattern. If another agent needs it, we'd namespace the var (e.g., `neph_pending_prompt_pi`). Not needed now.
