# Project Documentation

## Overview
Neph.nvim is a Neovim plugin for interactive code review using LLMs. It acts as an integration layer, providing terminal management, status bridging, and interactive diff reviews. It ensures agents do not interact with Neovim directly by using an intermediate policy and routing layer.

## Architecture

The system enforces a strict boundary where agents interact with the Cupcake policy layer, which invokes a CLI bridge to signal Neovim.

```mermaid
graph TD
    A[Agents: Claude, Cursor, Gemini, Copilot, Pi, OpenCode, Amp, Goose, Codex, Crush] -->|Hook/Plugin| B(Cupcake: Policy + Routing)
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
| `status.set` | Sets a `vim.g` global variable. Parameters: `name`, `value`. |
| `status.unset` | Unsets a `vim.g` global variable. Parameters: `name`. |
| `status.get` | Gets a `vim.g` global variable. Parameters: `name`. |
| `buffers.check` | Calls `:checktime` to sync files. |
| `tab.close` | Closes the current tab. |
| `ui.select` | Select UI option. Parameters: `request_id`, `channel_id`, `title`, `options`. |
| `ui.input` | Input UI. Parameters: `request_id`, `channel_id`, `title`, `default`. |
| `ui.notify` | Notify UI. Parameters: `message`, `level`. |
| `tools.status` | Get tools status. |
| `tools.install` | Install tool. Parameters: `name`. |
| `tools.install_all` | Install all tools. |
| `tools.uninstall` | Uninstall tool. Parameters: `name`. |
| `tools.preview` | Preview tools. |
| `review.status` | Get review status. |
| `review.accept` | Accept review. Optional Parameters: `idx`. |
| `review.reject` | Reject review. Optional Parameters: `idx`, `reason`. |
| `review.accept_all` | Accept all reviews. |
| `review.reject_all` | Reject all reviews. Optional Parameters: `reason`. |
| `review.submit` | Submit review. |
| `review.next` | Next review. |

## Changelog
* [2026-06-04 16:21:09]: Updated API Endpoints and Architecture to reflect new UI/tools/review RPC methods and supported agents.
* [2026-04-07 16:07:50]: Initial documentation created aggregating Architecture, Flows, and RPC API.
