# Project Documentation

## Overview
Neph.nvim is a Neovim plugin for interactive code review using LLMs. It acts as an integration layer, providing terminal management, status bridging, and interactive diff reviews. It ensures agents do not interact with Neovim directly by using an intermediate policy and routing layer.

## Architecture

The system enforces a strict boundary where agents interact with the Cupcake policy layer, which invokes a CLI bridge to signal Neovim.

```mermaid
graph TD
    A[Agents: Claude, Gemini, Pi, OpenCode] -->|Hook/Plugin| B(Cupcake: Policy + Routing)
    B -->|neph_review signal| C(neph-cli: Editor Abstraction)
    C -->|Msgpack RPC| D[Neovim: neph.nvim vimdiff]
    D -->|RPC Response| C
    C -->|Signal Result| B
    B -->|Agent Format| A
```

## Key Flows

### Interactive Review Flow

This flow triggers when an agent proposes file modifications.

```mermaid
sequenceDiagram
    participant A as Agent
    participant C as Cupcake
    participant NCLI as neph-cli
    participant NV as Neovim

    A->>C: Propose write/edit (Hook)
    C->>C: Evaluate policies (block rm -rf, protect .env)
    C->>NCLI: Run neph_review (normalize to path, content)
    NCLI->>NV: RPC review.open
    NV-->>NV: User reviews in vimdiff (ga/gr)
    NV->>NCLI: Return decision & content
    NCLI->>C: Signal result
    C->>A: Formatted response (accept/reject/partial)
```

## API Endpoints

The project uses a custom RPC protocol (`neph-rpc/v1`) between the `neph-cli` and Neovim over Unix sockets (`$NVIM`).

| Method | Description |
|--------|-------------|
| `review.open` | Opens an interactive vimdiff review. Returns `{ decision, content, hunks, reason }`. |
| `review.status` | Returns the current review status including active state, file, total, accepted, rejected, and undecided hunks. |
| `review.accept` | Accepts a specific hunk or the next undecided hunk. Returns `{ ok, idx, next }`. |
| `review.reject` | Rejects a specific hunk or the next undecided hunk with an optional reason. Returns `{ ok, idx, next }`. |
| `review.accept_all` | Accepts all remaining undecided hunks. Returns `{ ok, count }`. |
| `review.reject_all` | Rejects all remaining undecided hunks with an optional reason. Returns `{ ok, count }`. |
| `review.submit` | Finalizes the review. Returns `{ ok }`. |
| `review.next` | Jumps to the next undecided hunk. Returns `{ ok, idx }`. |
| `status.set` | Sets a `vim.g` global variable. |
| `status.get` | Gets a `vim.g` global variable. |
| `status.unset` | Unsets a `vim.g` global variable. |
| `buffers.check` | Calls `:checktime` to sync files. |
| `tab.close` | Closes the current tab. |
| `ui.select` | Displays a selection list UI prompt. Returns `{ ok }`. |
| `ui.input` | Displays a text input UI prompt. Returns `{ ok }`. |
| `ui.notify` | Displays a notification message. Returns `{ ok }`. |
| `tools.status` | Returns the installation status of all agent tools. |
| `tools.install` | Installs the specified agent tools. Returns `{ ok }`. |
| `tools.install_all` | Installs all agent tools. Returns `{ ok }`. |
| `tools.uninstall` | Uninstalls the specified agent tools. Returns `{ ok }`. |
| `tools.preview` | Returns a preview of changes that would be applied during tool installation. |


## Changelog
* [2026-04-07 16:07:50]: Initial documentation created aggregating Architecture, Flows, and RPC API.
* [2026-06-23 16:27:28]: Updated API Endpoints due to addition of UI, tools, and review RPC methods.
