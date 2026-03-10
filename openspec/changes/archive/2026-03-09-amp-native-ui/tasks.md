## 1. Setup & Configuration

- [x] 1.1 Update `lua/neph/agents/amp.lua` to include `PLUGINS=all` in the agent's environment variables.
- [x] 1.2 Update `tools/amp/package.json` to include `neovim` and other necessary dependencies for `NephClient`.

## 2. Amp Persistent Bridge Implementation

- [x] 2.1 Refactor `tools/amp/neph-plugin.ts` to initialize a persistent `NephClient`.
- [x] 2.2 Implement the `session.start` hook to connect, register as "amp", and set up the `neph:prompt` listener.
- [x] 2.3 Implement `agent.start` and `agent.end` hooks to manage the `amp_running` status variable.
- [x] 2.4 Transition the `tool.call` review logic to use `neph.review()` instead of the CLI-based `review()` helper.
- [x] 2.5 Implement the `ctx.ui` wrapper to redirect `notify`, `confirm`, and `input` to Neovim.

## 3. Testing & Validation

- [x] 3.1 Create `tools/amp/tests/amp.test.ts` to verify the persistent bridge logic and SDK hooks.
- [x] 3.2 Add integration tests in `tools/neph-cli/tests/` (if applicable) or verify via manual session.
- [x] 3.3 Verify that the `PLUGINS=all` environment variable correctly enables plugin loading in Amp.
