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
| `ui.select` | Prompts the user to select an option via `vim.ui.select`. |
| `ui.input` | Prompts the user for input via `vim.ui.input`. |
| `ui.notify` | Shows a notification via `vim.notify`. |
| `tools.status` | Gets the installation status of tools/agents. |
| `tools.install` | Installs a specific tool/agent. |
| `tools.install_all` | Installs all available tools/agents. |
| `tools.uninstall` | Uninstalls a specific tool/agent. |
| `tools.preview` | Shows a preview of what tools.install would change. |
| `review.status` | Gets the status of the active review. |
| `review.accept` | Accepts a review or a specific hunk. |
| `review.reject` | Rejects a review or a specific hunk. |
| `review.accept_all` | Accepts all remaining hunks in a review. |
| `review.reject_all` | Rejects all remaining hunks in a review. |
| `review.submit` | Submits the current review. |
| `review.next` | Advances to the next hunk in the review. |

## Changelog
* [2026-04-07 16:07:50]: Initial documentation created aggregating Architecture, Flows, and RPC API.
* [2026-06-19 16:11:21]: Updated API Endpoints table to align with protocol.json, removing bus.register and adding ui, tools, and review methods.
