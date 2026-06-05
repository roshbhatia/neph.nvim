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
| `status.set` | Sets a `vim.g` global variable. |
| `status.get` | Gets a `vim.g` global variable. |
| `status.unset` | Unsets a `vim.g` global variable. |
| `buffers.check` | Calls `:checktime` to sync files. |
| `tab.close` | Closes the current tab. |
| `bus.register` | Registers an extension agent's RPC channel (Internal). |
| `ui.select` | Shows a selection list. Requires `request_id`, `channel_id`, `title`, `options`. |
| `ui.input` | Shows a text input prompt. Requires `request_id`, `channel_id`, `title`, `default`. |
| `ui.notify` | Displays a notification. Requires `message`, `level`. |
| `tools.status` | Returns a status table for all agents' tools. |
| `tools.install` | Installs tools for a specified agent. Requires `name`. |
| `tools.install_all` | Installs all tools for all agents. |
| `tools.uninstall` | Uninstalls tools for a specified agent. Requires `name`. |
| `tools.preview` | Returns a formatted preview string of what install would change. |
| `review.status` | Returns the status of the active review. |
| `review.accept` | Accepts a hunk in the active review. Optional `idx`. |
| `review.reject` | Rejects a hunk in the active review. Optional `idx`, `reason`. |
| `review.accept_all` | Accepts all remaining hunks in the active review. |
| `review.reject_all` | Rejects all remaining hunks in the active review. Optional `reason`. |
| `review.submit` | Submits the active review. |
| `review.next` | Jumps to the next undecided hunk in the active review. |

## Changelog
* [2026-06-05 16:34:34]: Updated API Endpoints section to include missing methods from protocol.json.
* [2026-04-07 16:07:50]: Initial documentation created aggregating Architecture, Flows, and RPC API.
