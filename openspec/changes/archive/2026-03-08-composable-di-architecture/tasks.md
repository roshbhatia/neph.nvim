## 1. Contract Validation

- [x] 1.1 Create `lua/neph/internal/contracts.lua` with `validate_agent(def)` — asserts required fields (name, label, icon, cmd as strings), validates optional fields (args as table, send_adapter as function, integration as table)
- [x] 1.2 Add `validate_backend(mod, name)` to contracts.lua — asserts required methods (setup, open, focus, hide, is_visible, kill, cleanup_all) are functions
- [x] 1.3 Add tests for contracts module in `tests/contracts_spec.lua` — valid/invalid agents, valid/invalid backends, edge cases (missing fields, wrong types)

## 2. Agent Submodules

- [x] 2.1 Create `lua/neph/agents/` directory with individual agent files: claude.lua, goose.lua, opencode.lua, amp.lua, copilot.lua, gemini.lua, codex.lua, crush.lua, cursor.lua, pi.lua — each returning an AgentDef table extracted from current agents.lua
- [x] 2.2 Create `lua/neph/agents/all.lua` — requires and returns array of all 10 agent submodules
- [x] 2.3 Add tests for agent submodules in `tests/agent_submodules_spec.lua` — each module returns valid AgentDef, all.lua returns correct count, pi includes send_adapter

## 3. Backend Submodules

- [x] 3.1 Move `lua/neph/internal/backends/native.lua` to `lua/neph/backends/snacks.lua` — preserve all existing behavior
- [x] 3.2 Move `lua/neph/internal/backends/wezterm.lua` to `lua/neph/backends/wezterm.lua` — preserve all existing behavior
- [x] 3.3 Delete `lua/neph/internal/backends/tmux.lua` and `lua/neph/internal/backends/zellij.lua` (stubs)
- [x] 3.4 Delete empty `lua/neph/internal/backends/` directory

## 4. Config Module Update

- [x] 4.1 Update `lua/neph/config.lua` — replace `multiplexer` with `backend = nil` in defaults, remove `enabled_agents` from type annotation, change `agents` type from `neph.AgentDef[]` to the injected array type
- [x] 4.2 Update `neph.Config` type annotation — add `backend` field (table), remove `multiplexer` and `enabled_agents` fields

## 5. Core Wiring (init.lua + session.lua + agents.lua)

- [x] 5.1 Rewrite `lua/neph/init.lua` setup() — validate agents array via contracts, validate backend via contracts, pass agents to internal.agents.init(), pass backend to session.setup()
- [x] 5.2 Rewrite `lua/neph/internal/agents.lua` — remove hardcoded agent list, remove merge(), add init(agent_defs) that receives the injected array, keep get_all() and get_by_name() as accessors with executable filtering
- [x] 5.3 Rewrite `lua/neph/internal/session.lua` setup() — remove detect_backend() and if/elseif chain, accept backend module as parameter, use it directly for all operations

## 6. Internal Consumer Updates

- [x] 6.1 Update `lua/neph/internal/picker.lua` — ensure it reads agents from the accessor (agents.get_all()), no hardcoded agent names
- [x] 6.2 Update any remaining internal requires of `neph.internal.backends.*` to use the injected backend reference
- [x] 6.3 Update `lua/neph/tools.lua` — ensure install_async() respects injected agents for selective installation

## 7. Test Updates

- [x] 7.1 Update `tests/agents_spec.lua` — test new init() + get_all() + get_by_name() accessor pattern, remove tests for merge()
- [x] 7.2 Update `tests/config_spec.lua` — test new defaults (no multiplexer, no enabled_agents, backend = nil)
- [x] 7.3 Update `tests/session_spec.lua` — test setup() accepts backend module directly, no detect_backend() tests
