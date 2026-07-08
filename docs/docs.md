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
| `ui.select` | Shows a selection list UI. Returns user choice. |
| `ui.input` | Shows a text input prompt UI. Returns user input. |
| `ui.notify` | Displays a notification message. |
| `tools.status` | Retrieves the status of installed agent tools. |
| `tools.install` | Installs a specific agent tool. |
| `tools.install_all` | Installs all agent tools. |
| `tools.uninstall` | Uninstalls a specific agent tool. |
| `tools.preview` | Previews agent tools configuration. |
| `review.status` | Gets the status of the current active review session. |
| `review.accept` | Accepts the current review hunk or session. |
| `review.reject` | Rejects the current review hunk or session. |
| `review.accept_all` | Accepts all review hunks. |
| `review.reject_all` | Rejects all review hunks. |
| `review.submit` | Submits the completed review session. |
| `review.next` | Moves to the next review hunk. |

## Changelog
* [2026-07-08 16:27:55]: Updated API Endpoints table to include new `ui.*`, `tools.*`, and `review.*` methods, and removed deprecated `bus.register`.
* [2026-04-07 16:07:50]: Initial documentation created aggregating Architecture, Flows, and RPC API.
