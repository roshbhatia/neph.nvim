# Project Documentation

## Overview
**neph.nvim** is a Neovim integration layer for AI agents. It provides a universal bridge between AI coding agents and Neovim, enabling interactive diff reviews, state management, and tool discovery through a clean RPC interface. It ensures agents never communicate directly with Neovim, but instead go through a policy evaluation layer (Cupcake) which then invokes `neph-cli` for interactive review.

## Architecture
The project uses a composable Dependency Injection (DI) architecture. Agents and backends are standalone submodules passed into `setup()` via constructor injection.

```mermaid
graph TD
    subgraph Agents
        Claude
        Gemini
        Pi
        OpenCode
    end

    subgraph Core
        Cupcake[Cupcake Policy Layer<br/>Rego/Wasm policies]
        NephCLI[neph-cli<br/>Node.js Bridge]
    end

    subgraph Neovim
        Vimdiff[Vimdiff Review UI]
        Status[Status Management]
    end

    Claude -->|Hook| Cupcake
    Gemini -->|Hook| Cupcake
    Pi -->|Hook| Cupcake
    OpenCode -->|Plugin| Cupcake

    Cupcake -->|Signals: neph_review| NephCLI
    NephCLI -->|RPC| Vimdiff
    NephCLI -->|RPC| Status
    Vimdiff -.->|Decision| NephCLI
    NephCLI -.->|Result| Cupcake
    Cupcake -.->|Response| Agents
```

## Key Flows

### Interactive Review Flow
```mermaid
sequenceDiagram
    participant Agent
    participant Cupcake
    participant neph-cli
    participant Neovim

    Agent->>Cupcake: Proposes file write/edit tool call
    Cupcake->>Cupcake: Evaluates deterministic policies (e.g. block dangerous ops)
    Cupcake->>neph-cli: Signal neph_review (path, content)
    neph-cli->>Neovim: RPC review.open(request_id, path, content)
    Neovim->>Neovim: Opens vimdiff tab for user review
    Note over Neovim: User accepts/rejects hunks interactively
    Neovim-->>neph-cli: Writes ReviewEnvelope and notifies channel
    neph-cli-->>Cupcake: Returns decision and content
    Cupcake-->>Agent: Returns decision in agent-specific format
```

## API Endpoints
The Neph RPC protocol (`neph-rpc/v1`) defines the contract between external processes and Neovim.

| Method | Params | Async | Description |
|--------|--------|-------|-------------|
| `review.open` | `request_id`, `path`, `content` | Yes | Opens an interactive vimdiff review. |
| `status.set` | `name`, `value` | No | Sets a `vim.g` global variable. |
| `status.get` | `name` | No | Gets a `vim.g` global variable. |
| `status.unset` | `name` | No | Unsets a `vim.g` global variable. |
| `buffers.check` | (none) | No | Calls `:checktime` in Neovim. |
| `tab.close` | (none) | No | Closes the current tab. |
| `ui.select` | `request_id`, `channel_id`, `title`, `options` | Yes | Opens a selection UI. |
| `ui.input` | `request_id`, `channel_id`, `title`, `default` | Yes | Opens an input UI. |
| `ui.notify` | `message`, `level` | No | Displays a notification. |

## Changelog
* **2026-03-26 (v1.0.0):**
  * Add `:NephReview` command for manual buffer-vs-disk review.
  * Add agent integrations for claude, copilot, cursor, gemini, amp, opencode.
  * Implement multi-protocol architecture with neph CLI.
  * Replace gate/bus/NephClient with Cupcake as sole integration layer.
  * Overhaul review diff UI with dual signs, walkback, and explicit submit.
  * Implement composable DI architecture for agents and backends.

*Last Updated: 2026-03-26*
