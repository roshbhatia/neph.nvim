## 1. Integration Pipeline Scaffolding

- [x] 1.1 Add config schema for integration groups, policy engine, and reviewer opt-in
- [x] 1.2 Implement canonical event/decision types and pipeline resolution logic
- [x] 1.3 Add noop policy engine and noop review provider implementations
- [x] 1.4 Wire pipeline resolution into agent integration entry points

## 2. Review Provider Opt-In

- [x] 2.1 Add reviewer registry module and noop default
- [x] 2.2 Gate Neovim diff review and `:NephReview` on reviewer registration

## 3. CLI Integration Commands

- [x] 3.1 Implement `neph integration toggle` (interactive + named)
- [x] 3.2 Implement `neph integration status` with `--show-config`
- [x] 3.3 Implement `neph deps status` dependency checks
- [x] 3.4 Add CLI tests for integration/deps commands

## 4. Tool Install and NephTools Deprecation

- [x] 4.1 Remove or stub Neovim `:NephTools` install flow
- [x] 4.2 Remove Neovim startup install hooks in `tools.lua`
- [x] 4.3 Update install docs to point at CLI integration commands

## 5. Checkhealth Integration Status

- [x] 5.1 Update `lua/neph/health.lua` to call CLI status commands
- [x] 5.2 Add Lua tests covering checkhealth CLI fallback behavior

## 6. Agent Group Defaults and Overrides

- [x] 6.1 Define group defaults for harness-backed vs hook-based agents
- [x] 6.2 Update agent definitions to reference integration groups/overrides

## 7. Documentation and Cleanup

- [x] 7.1 Update `tools/README.md` with composable pipeline and CLI usage
- [x] 7.2 Remove or update references to NephTools in docs/tests
- [x] 7.3 Update `README.md` to include the NephReview keymap
