## 1. Tool Manifest Contract Validation

- [ ] 1.1 Add `validate_tools(agent)` to `lua/neph/internal/contracts.lua` — validates `tools.symlinks` (each has src+dst strings), `tools.merges` (each has src+dst+key strings), `tools.builds` (each has dir+src_dirs+check), `tools.files` (each has dst+content strings, mode is "create_only"|"overwrite")
- [ ] 1.2 Update `validate_agent()` to call `validate_tools()` when `tools` field is present
- [ ] 1.3 Add tool manifest validation tests in `tests/contracts_spec.lua` — valid manifests, missing fields, invalid modes, agent without tools passes

## 2. Agent Submodule Tool Manifests

- [ ] 2.1 Add `tools` field to `lua/neph/agents/pi.lua` — symlinks (package.json, dist), builds (pi dir), files (index.ts with create_only)
- [ ] 2.2 Add `tools` field to `lua/neph/agents/claude.lua` — merges (settings.json hooks)
- [ ] 2.3 Add `tools` field to `lua/neph/agents/gemini.lua` — merges (settings.json hooks)
- [ ] 2.4 Add `tools` field to `lua/neph/agents/cursor.lua` — symlinks (hooks.json)
- [ ] 2.5 Add `tools` field to `lua/neph/agents/amp.lua` — symlinks (neph-plugin.ts)
- [ ] 2.6 Add `tools` field to `lua/neph/agents/opencode.lua` — symlinks (write.ts, edit.ts)
- [ ] 2.7 Update `tests/agent_submodules_spec.lua` — verify agents with tools have valid manifests via validate_tools()

## 3. Rewrite tools.lua

- [ ] 3.1 Remove hardcoded TOOLS, MERGE_TOOLS tables — replace with generic iteration over `agents.get_all()` reading each agent's `tools` manifest
- [ ] 3.2 Remove hardcoded `builds` list — collect from agents' `tools.builds` manifests, keep neph-cli as the sole hardcoded build
- [ ] 3.3 Remove pi-specific `post_install` block — replaced by `files` manifest on pi agent
- [ ] 3.4 Add `files` manifest processing — create files with content based on mode (create_only/overwrite)
- [ ] 3.5 Verify zero agent names remain in tools.lua (only "neph-cli" for universal tool)

## 4. Integration Tests

- [ ] 4.1 Add `tests/backend_conformance_spec.lua` — snacks and wezterm backends pass `validate_backend()`
- [ ] 4.2 Add setup smoke test in `tests/setup_smoke_spec.lua` — full setup() with real agents + stub backend wires correctly
- [ ] 4.3 Add setup negative path tests in `tests/setup_smoke_spec.lua` — missing backend throws, invalid agent throws, invalid backend throws, malformed tools manifest throws
