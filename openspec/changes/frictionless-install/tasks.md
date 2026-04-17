# Tasks: Frictionless Install

## 1. Integration interface — add globalConfigPath

- [x] 1.1 Add optional `globalConfigPath?: () => string` to `Integration` interface in `integration.ts`
- [x] 1.2 Populate `globalConfigPath` for gemini (`~/.gemini/settings.json`), cursor (`~/.cursor/hooks.json`), codex (`~/.codex/hooks.json`)
- [x] 1.3 Leave `globalConfigPath` absent for claude, opencode

## 2. detectNephBin()

- [x] 2.1 Implement `detectNephBin(): string` in `integration.ts`
  - Prefer `process.env.NEPH_BIN` (for tests and CI overrides)
  - Fall back to `process.argv[1]` (the script/bundle path)
- [x] 2.2 Unit test: `NEPH_BIN` env var is respected
- [x] 2.3 Unit test: falls back to `process.argv[1]` when env var absent

## 3. substituteNephBin()

- [x] 3.1 Implement `substituteNephBin(template: JsonValue, binPath: string): JsonValue`
  - Deep-clones the template object
  - Replaces every `command` string that contains `neph integration hook` with
    one using `binPath` as the prefix instead of any existing PATH prefix
  - Uses `normalizeCommand()` to strip existing prefix, then prepends `binPath`
- [x] 3.2 Unit tests: substitutes correctly for hooks-style and copilot-style templates

## 4. neph print-settings

- [x] 4.1 Implement `runPrintSettingsCommand(args: string[])` in `integration.ts`
  - Validates agent argument
  - Reads template, writes minified JSON to stdout
  - Error cases per spec
- [x] 4.2 Wire `print-settings` subcommand in `index.ts`
- [x] 4.3 Tests:
  - Prints valid JSON for each known agent
  - Errors on unknown agent
  - Errors on cupcake integration (no template)

## 5. neph install

- [x] 5.1 Implement `runInstallCommand(args: string[])` in `integration.ts`
  - Resolves agent list (all or single)
  - For each agent with `globalConfigPath`: detect bin, substitute, merge, write
  - For claude: skip file write, mark for alias output
  - Print per-agent status lines
  - Print gemini warning if gemini was installed
  - Print shell alias block
- [x] 5.2 Wire `install` subcommand in `index.ts`
- [x] 5.3 Tests (sandbox-style, tmpdir):
  - Creates global config when file absent
  - Merges into existing global config without clobbering unrelated entries
  - Idempotent: running twice produces same result
  - Single-agent: `neph install gemini` only touches gemini
  - Absolute binary path embedded in written commands (uses `NEPH_BIN` override in test)
  - Claude: no file written, alias printed
  - Gemini warning printed

## 6. neph uninstall

- [x] 6.1 Implement `runUninstallCommand(args: string[])` in `integration.ts`
  - Mirrors install: reads global config, unmerges, writes or removes
  - Prints per-agent status
- [x] 6.2 Wire `uninstall` subcommand in `index.ts`
- [x] 6.3 Tests:
  - Removes neph entries, preserves non-neph entries
  - Removes file entirely when result is empty
  - No-ops gracefully when file absent
  - Single-agent uninstall

## 7. index.ts help text

- [x] 7.1 Add `install`, `uninstall`, `print-settings` to usage string in `index.ts`

## 8. AGENTS.md docs

- [x] 8.1 Add section documenting `neph install` workflow
- [x] 8.2 Document `neph print-settings` and the shell alias pattern
- [x] 8.3 Note that `neph integration toggle` remains for per-project override

## Definition of Done

- All tasks above checked
- `npx vitest run` — 0 failures (outside pre-existing worktree failures)
- `tsc --noEmit` — 0 errors
- Manual smoke test: `NEPH_BIN=/usr/bin/true neph install` produces correct output
  and writes correctly merged config files
