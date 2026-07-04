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
| `review.status` | Returns the status of the active review session. |
| `review.accept` | Accepts a specific hunk by index in the active review. |
| `review.reject` | Rejects a specific hunk by index with an optional reason. |
| `review.accept_all` | Accepts all remaining undecided hunks in the active review. |
| `review.reject_all` | Rejects all remaining undecided hunks in the active review with an optional reason. |
| `review.submit` | Submits the active review, finalizing decisions. |
| `review.next` | Navigates to the next undecided hunk in the active review. |
| `status.set` | Sets a `vim.g` global variable. |
| `status.get` | Gets a `vim.g` global variable. |
| `status.unset` | Unsets a `vim.g` global variable. |
| `buffers.check` | Calls `:checktime` to sync files. |
| `tab.close` | Closes the current tab. |
| `ui.select` | Shows a selection list using `vim.ui.select`. |
| `ui.input` | Shows a text input prompt using `vim.ui.input`. |
| `ui.notify` | Displays a notification using `vim.notify`. |
| `tools.status` | Returns the installation status of tools for all registered agents. |
| `tools.install` | Installs tools for a specified agent. |
| `tools.install_all` | Installs tools for all registered agents. |
| `tools.uninstall` | Uninstalls tools for a specified agent. |
| `tools.preview` | Returns a preview of what `tools.install` would change. |
| `bus.register` | Registers an extension agent's RPC channel (Internal). |

## Changelog
* [2026-04-07 16:07:50]: Initial documentation created aggregating Architecture, Flows, and RPC API.
* [2026-07-04 16:15:52]: Updated API Endpoints due to new methods added in protocol.json.
