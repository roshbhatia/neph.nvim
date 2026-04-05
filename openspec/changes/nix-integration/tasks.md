## 1. Template metadata: add `_kind` to hook entries

- [x] 1.1 Add `"_kind": "lifecycle"` to SessionStart/End/UserPromptSubmit/Stop entries in `tools/claude/settings.json`; add `"_kind": "review"` to PreToolUse/PostToolUse entries
- [x] 1.2 Add `_kind` metadata to `tools/gemini/settings.json` — lifecycle: SessionStart/End/BeforeAgent/AfterAgent; review: BeforeTool/AfterTool
- [x] 1.3 Add `_kind` metadata to `tools/cursor/hooks.json` — all cursor hooks are `"lifecycle"` (cursor has no pre-write review; afterFileEdit/beforeShell/beforeMCP are all infrastructure)
- [x] 1.4 Add `_kind` metadata to `tools/copilot/hooks.json` — lifecycle: sessionStart/sessionEnd; review: preToolUse/postToolUse
- [x] 1.5 Add `_kind` metadata to `tools/codex/hooks.json` — lifecycle: UserPromptSubmit/Stop; review: PreToolUse/PostToolUse

## 2. CLI: strip `_kind` before writing to disk

- [x] 2.1 Add `stripKind(entry)` helper in `integration.ts` that removes `_kind` from a hook entry object
- [x] 2.2 Apply `stripKind` in `mergeHooks` before pushing entries to the output config
- [x] 2.3 Apply `stripKind` in `mergeCopilot` before pushing entries
- [x] 2.4 Add unit test: `neph integration toggle claude` written config has no `_kind` fields

## 3. Nix home-manager module

- [x] 3.1 Create `nix/hm-module.nix` — `programs.neph` options: `enable`, `integrations.{claude,gemini,cursor,copilot,codex}` (all default true)
- [x] 3.2 Implement lifecycle hook filtering in the module: read template JSON, filter entries where `_kind == "lifecycle"`, strip `_kind` before injecting
- [x] 3.3 Wire Claude integration: `programs.claude-code.settings.hooks` merges lifecycle hooks when `cfg.integrations.claude` is true
- [x] 3.4 Wire Gemini integration: `home.file.".gemini/settings.json"` writes lifecycle hooks JSON
- [x] 3.5 Wire Cursor integration: `home.file.".cursor/hooks.json"` writes all cursor hooks (all lifecycle)
- [x] 3.6 Wire Copilot integration: `home.file.".copilot/hooks.json"` writes sessionStart/sessionEnd hooks
- [x] 3.7 Wire Codex integration: `home.file.".codex/hooks.json"` writes UserPromptSubmit/Stop hooks

## 4. flake.nix: export homeManagerModules

- [x] 4.1 Add `homeManagerModules.default = import ./nix/hm-module.nix;` to `flake.nix` outputs
- [x] 4.2 Verify `nix flake show` lists `homeManagerModules.default`

## 5. sysinit: wire neph.nvim as flake input

- [x] 5.1 Add `neph-nvim.url = "github:roshbhatia/neph.nvim"` to `sysinit/flake.nix` inputs
- [x] 5.2 Pass `neph-nvim` through `extraSpecialArgs` so it's available to home modules (already satisfied — `inputs` passed wholesale)
- [x] 5.3 Create `sysinit/modules/home/programs/llm/config/neph.nix` that imports `inputs.neph-nvim.homeManagerModules.default` and sets `programs.neph.enable = true`
- [x] 5.4 Import `./config/neph.nix` in `sysinit/modules/home/programs/llm/default.nix`
- [x] 5.5 Remove the manually-added neph hooks from `sysinit/modules/home/programs/llm/config/claude.nix` (now handled by the module)
- [ ] 5.6 Run `home-manager switch` (or equivalent) and verify `~/.claude/settings.json` contains neph lifecycle hooks, `~/.cursor/hooks.json` contains neph hooks
