## 1. Neph CLI UI Commands

- [ ] 1.1 Update `tools/neph-cli/src/index.ts` to implement the `ui-select` command (waiting for notification)
- [ ] 1.2 Implement the `ui-input` command in the CLI (waiting for notification)
- [ ] 1.3 Implement the `ui-notify` command in the CLI (fire-and-forget)
- [ ] 1.4 Update `tools/lib/neph-run.ts` with `uiSelect`, `uiInput`, and `uiNotify` helper functions that wrap the CLI

## 2. OpenCode Persistent Bridge

- [ ] 2.1 Create `tools/opencode/opencode.ts` and initialize a `NephClient`
- [ ] 2.2 Implement the `session.busy` and `session.idle` SDK hooks to push status to Neovim
- [ ] 2.3 Implement the `tool.execute.before` hook to intercept `shell` tool calls and trigger `uiSelect` for approval
- [ ] 2.4 Set up the `neph:prompt` listener to forward Neovim prompts to OpenCode
- [ ] 2.5 Ensure the bridge correctly registers as the `opencode` agent upon initialization

## 3. Agent Configuration & Symlinks

- [ ] 3.1 Update `lua/neph/agents/opencode.lua` to change the agent type to `extension`
- [ ] 3.2 Add a symlink in `opencode.lua` for `opencode/opencode.ts` to `~/.config/opencode/plugin/neph-companion.ts`
- [ ] 3.3 Ensure the `opencode` agent definition includes the necessary build/install steps if required

## 4. Testing & Validation

- [ ] 4.1 Add unit tests for the new CLI commands using `FakeTransport`
- [ ] 4.2 Add Vitest unit tests for the `opencode` persistent bridge logic
- [ ] 4.3 Verify the end-to-end flow: status updates and shell approval prompts in a manual test session
