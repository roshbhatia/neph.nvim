# Neph Architecture

Neph.nvim is a Neovim integration layer for AI agents. It provides a universal bridge between external agentic processes and Neovim, enabling interactive reviews, state management, and tool discovery.

## Component Boundaries

### 1. Neovim Bridge CLI (`neph`)
A Node.js/TypeScript CLI (`tools/neph-cli/`) that serves as the entry point for all external consumers:
- **RPC Agents**: Extension-based agents like `pi` that spawn `neph` as a subprocess to communicate with Neovim.
- **PATH Tools**: Standalone CLI tools (e.g., `claude code`, `amp`) that discover `neph` on the system `PATH`.

### 2. RPC Dispatch Facade (`lua/neph/rpc.lua`)
A single Lua module that routes all incoming RPC requests from the `neph` CLI to internal API modules. It handles:
- Method routing
- Error normalization
- Pcall-wrapped execution

### 3. API Modules (`lua/neph/api/`)
Stateless modules implementing specific capabilities:
- `review/`: Core diff review logic and UI.
- `status.lua`: Global state management (`vim.g`), including the `status.get` RPC for reading state variables.
- `buffers.lua`: Buffer and tab operations.

### 4. Review Engine vs. UI
The review system is split into two layers:
- **Engine** (`lua/neph/api/review/engine.lua`): Pure logic for hunk computation and decision application. Testable in headless Neovim.
- **UI** (`lua/neph/api/review/ui.lua`): Thin Neovim adapter managing signs, virtual text, and the `Snacks.picker` selection loop.

### 5. Send Adapters & Prompt Delivery
Prompt delivery is decoupled using agent-specific **send adapters**. For example, the `pi` adapter sets `vim.g.neph_pending_prompt` for programmatic delivery. Extensions then poll these state variables using the `neph get` CLI command to retrieve and process pending prompts asynchronously.

### 6. Dependency Injection (DI)
Agents and backends are standalone submodules passed directly into `setup()` via constructor injection. This replaces the hardcoded agent list and multiplexer string enum, enabling greater composability and testability.

## Architecture

```mermaid
graph TD
    Config[setup() Configuration] -->|injects| InjectedAgents[Agent Submodules]
    Config -->|injects| InjectedBackend[Backend Submodule]

    InjectedAgents --> Agent
    InjectedBackend --> UI

    Agent[AI Agent / PATH Tool] -->|spawns| CLI[Neph CLI]
    Ext[Agent Extension e.g., Pi] -.->|polls neph get| CLI

    CLI -->|msgpack-rpc| RPC[RPC Dispatch Facade lua/neph/rpc.lua]

    RPC --> API_Review[API: review/]
    RPC --> API_Status[API: status.lua]
    RPC --> API_Buffers[API: buffers.lua]

    API_Review --> Engine[Review Engine]
    API_Review --> UI[Review UI Snacks.picker]

    Engine --> Envelope[ReviewEnvelope JSON]
    UI --> Envelope
    Envelope -->|rpcnotify via temp file| CLI

    API_Status --> State[vim.g state]
    State -.->|neph_pending_prompt| Ext

    CLI -->|stdout| Agent
```

## Data Flow: Interactive Review

1. **Agent** spawns `neph review <path>` with proposed content on `stdin`.
2. **`neph`** discovers the Neovim socket and calls `review.open` via `rpc.lua`.
3. **`rpc.lua`** dispatches to `neph.api.review.open`.
4. **Neovim** opens a diff tab and starts the interactive `Snacks.picker` loop.
5. **User** makes per-hunk decisions.
6. **Review Engine** builds a `ReviewEnvelope` JSON.
7. **Neovim** writes the result to a temp file and fires an `rpcnotify`.
8. **`neph`** receives the notification, reads the result, prints JSON to `stdout`, and exits.
9. **Agent** parses `stdout` and continues its workflow.

## Protocols

- **Neovim RPC**: Standard msgpack-rpc over Unix sockets.
- **Neph RPC**: A custom method+params contract defined in `protocol.json`.
- **Review Protocol**: Asynchronous, request-id-correlated exchange via temp files and notifications.

## Changelog

- **[2026-03-08 16:07:55]** Introduced a composable DI architecture. Replaced hardcoded agent lists and multiplexer enums with standalone agent and backend submodules passed directly into `setup()` via constructor injection.
- **[2026-03-08 10:15:00]** Decoupled prompt delivery by introducing send adapters. Agent extensions like `pi` can now poll `vim.g.neph_pending_prompt` via the new `neph get` CLI tool and `status.get` RPC.
- **[Last Known Hash]:** bfd35b36487d9e039de893655761528f344cf1af
