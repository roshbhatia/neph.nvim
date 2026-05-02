# Manual test plan — frictionless-by-default

These checks need a real Neovim + WezTerm session, so they're handed off to you. Each one is short. Run them in any order; they're independent.

## Prereqs

```bash
# Make sure the CLI symlink is fresh after the build
:NephBuild  # or: bash scripts/build.sh
which neph  # → ~/.local/bin/neph
```

Confirm `claude`, `goose`, `pi` are on `$PATH`. For peer-adapter tests:

```bash
# claudecode.nvim
# Add to your lazy spec dependencies and reload:
#   { "coder/claudecode.nvim", lazy = true }

# opencode.nvim
#   { "nickjvandyke/opencode.nvim", lazy = true }
```

## 1. Open-by-default sanity (every agent)

In any project:

```vim
:lua print(require("neph.api").gate_status())   " → bypass
```

Open the picker (`<leader>jj`), pick **claude**. After it spawns:

- It should NOT prompt for permission on its first edit.
- A subsequent agent write should NOT pop a review tab — gate is bypass.
- `<leader>jg` once should land on `normal`. Cycling through `hold` and back to `bypass` should restore silent acceptance.
- The winbar should show `⏸ NEPH HOLD` when the gate is `hold` and `󰈑 NEPH BYPASS` when bypass is *explicitly cycled into* (no indicator on the default startup state).

## 2. claude (hook agent — existing path)

`<leader>jj` → claude → ask it to write to a file. With gate=bypass, the write is silently accepted via the cupcake hook. Cycle `<leader>jg` once to land on `normal` and re-test — review UI should now open.

## 3. goose (terminal agent — fs_watcher path)

`<leader>jj` → goose → ask it to modify a file. With gate=bypass the change lands directly. With gate=normal the fs_watcher picks it up and opens the review.

## 4. pi (extension agent — bus path)

`<leader>jj` → pi → ask it to comment a line. Bus connection should establish on first message. `<leader>jg` flow same as above.

## 5. claude-peer (requires claudecode.nvim)

Pick **claude-peer** from the picker. claudecode.nvim takes over the terminal; selection broadcasts should be live (move cursor in source buffer, ask claude "what file am I in?" — it should know without `+file`).

Ask claude to edit a file. Because `peer.override_diff = true`, claude's `openDiff` MCP call should route through neph's review queue (it's a queued review, not claudecode's vimdiff). With gate=bypass it auto-accepts; with gate=normal you should see neph's accept/reject UI before the write commits.

If claudecode.nvim isn't installed: picking `claude-peer` should fire a one-time notification "claudecode.nvim is not installed" — neph keeps working otherwise.

## 6. opencode-peer (requires opencode.nvim)

Pick **opencode-peer**. Send a prompt — opencode.nvim's prompt API handles it. Same fallback notification when the plugin is absent.

## 7. Auto-context broadcast

```bash
# In an agent pane (NVIM_SOCKET_PATH is set automatically):
neph context current
neph context current --field buffer.uri
```

Move the cursor in a source buffer in Neovim, then re-run — `cursor.line` should reflect the new position. Switch to a different file — `buffer.uri` should change. Open a visual selection — `buffer.selection.text` should populate.

```bash
# Stale check:
neph context current --max-age-ms 1
# Should print {"error":"stale_snapshot",...} unless your cursor moved within the last 1 ms.
```

## 8. Gate cycle UX

1. Start fresh Neovim. Gate = `bypass`. No winbar indicator (the indicator only renders on transitions).
2. `<leader>jg` → `normal`. Indicator clears (since normal has no indicator).
3. `<leader>jg` → `hold`. ⏸ NEPH HOLD appears.
4. Trigger an agent write — review accumulates silently.
5. `<leader>jg` → `bypass`. 󰈑 NEPH BYPASS appears.

If anything shows a stale or wrong state, run `:NephDebug tail` for the live log.

---

## Rollback

If "open by default" feels wrong:

```lua
require("neph.internal.gate").set("normal")  -- once per session
```

Or per project:
```jsonc
// .neoconf.json
{ "neph": { "gate": "normal" } }
```

Or revert agent flags by overriding in your `agents` list before passing to `setup()`.
