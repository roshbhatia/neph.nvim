## ADDED Requirements

### Requirement: Amp plugin adapter
neph.nvim SHALL include an Amp plugin at `tools/amp/neph-plugin.ts` that registers a `tool.call` event handler to intercept file write tool calls and route them through `neph review` using the shared `lib/neph-run.ts` module. The plugin SHALL use the `@ampcode/plugin` PluginAPI and include the required experimental acknowledgment comment.

#### Scenario: Amp write intercepted and accepted
- **WHEN** Amp invokes a file write tool (e.g., `create_file`) and the plugin's `tool.call` handler fires
- **THEN** the plugin SHALL call `review(filePath, content)` from `lib/neph-run.ts`
- **AND** return `{ action: 'allow' }` if the review decision is "accept"

#### Scenario: Amp write intercepted and rejected
- **WHEN** Amp invokes a file write tool and the review decision is "reject"
- **THEN** the plugin SHALL return `{ action: 'reject-and-continue', message: reason }` to block the tool call

#### Scenario: Amp edit intercepted
- **WHEN** Amp invokes `edit_file` and the plugin's `tool.call` handler fires
- **THEN** the plugin SHALL reconstruct the full file content, call `review()`, and return `reject-and-continue` if rejected

#### Scenario: Amp plugin manages statusline state
- **WHEN** the Amp plugin processes a review
- **THEN** it SHALL call `neph("set", "amp_active", "true")` and `neph("unset", "amp_active")` around the review

#### Scenario: Amp plugin uses filesModifiedByToolCall helper
- **WHEN** the plugin receives a tool.call event
- **THEN** it MAY use `filesModifiedByToolCall()` to extract file URIs from edit/create/apply_patch tools

### Requirement: OpenCode custom tool overrides
neph.nvim SHALL include OpenCode custom tools at `tools/opencode/write.ts` and `tools/opencode/edit.ts` that override the built-in `write` and `edit` tools to route file mutations through `neph review`. Tools SHALL use the `@opencode-ai/plugin` `tool()` helper with Zod-based schemas.

#### Scenario: OpenCode write overridden
- **WHEN** OpenCode invokes the `write` tool and `tools/opencode/write.ts` is installed in `.opencode/tools/` or `~/.config/opencode/tools/`
- **THEN** the override SHALL call `review(args.file_path, args.content)` from `lib/neph-run.ts` before writing to disk

#### Scenario: OpenCode write rejected
- **WHEN** the review decision is "reject"
- **THEN** the tool SHALL return a rejection message string without writing the file

#### Scenario: OpenCode edit overridden
- **WHEN** OpenCode invokes the `edit` tool and `tools/opencode/edit.ts` is installed
- **THEN** the override SHALL read the current file, apply the edit, call `review()` with the full content, and return a rejection message if rejected

#### Scenario: OpenCode tools use context.directory
- **WHEN** the OpenCode tool executes
- **THEN** it SHALL use `context.directory` for resolving relative file paths

#### Scenario: OpenCode adapter manages statusline state
- **WHEN** the OpenCode adapter processes a review
- **THEN** it SHALL call `neph("set", "opencode_active", "true")` and `neph("unset", "opencode_active")` around the review

### Requirement: TypeScript adapters use shared lib
Both `tools/amp/neph-plugin.ts` and `tools/opencode/write.ts`/`edit.ts` SHALL import `nephRun`, `review`, and `neph` from `tools/lib/neph-run.ts` rather than defining these functions inline.

#### Scenario: No duplicated nephRun logic
- **WHEN** the amp and opencode adapter source files are inspected
- **THEN** neither SHALL contain inline definitions of `nephRun`, `review`, or fire-and-forget `neph`
- **AND** all SHALL import from the shared lib

### Requirement: Amp plugin has no package.json requirement
Amp plugins are Bun-based and do not require a package.json. The plugin file SHALL be self-contained.

#### Scenario: Amp plugin is a single file
- **WHEN** `tools/amp/neph-plugin.ts` is inspected
- **THEN** it SHALL be a single TypeScript file with the `@i-know-the-amp-plugin-api-is-wip-and-very-experimental-right-now` acknowledgment comment

### Requirement: OpenCode tools have no package.json requirement
OpenCode custom tools are loaded directly from the tools directory and do not require a package.json.

#### Scenario: OpenCode tools are standalone files
- **WHEN** `tools/opencode/write.ts` and `tools/opencode/edit.ts` are inspected
- **THEN** they SHALL be standalone TypeScript files using the `@opencode-ai/plugin` `tool()` helper
