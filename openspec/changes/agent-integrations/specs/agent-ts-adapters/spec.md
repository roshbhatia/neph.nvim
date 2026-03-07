## ADDED Requirements

### Requirement: Amp plugin adapter
neph.nvim SHALL include an Amp plugin at `tools/amp/neph-plugin.ts` that registers a `tool.call` event handler to intercept file write tool calls (`edit_file`, `create_file`) and route them through `neph review` using the shared `lib/neph-run.ts` module.

#### Scenario: Amp write intercepted and accepted
- **WHEN** Amp invokes `create_file` and the plugin's `tool.call` handler fires
- **THEN** the plugin SHALL call `review(filePath, content)` from `lib/neph-run.ts`
- **AND** allow the tool call if the review decision is "accept"

#### Scenario: Amp write intercepted and rejected
- **WHEN** Amp invokes `create_file` and the review decision is "reject"
- **THEN** the plugin SHALL block the tool call and return the rejection reason to the agent

#### Scenario: Amp edit intercepted
- **WHEN** Amp invokes `edit_file` and the plugin's `tool.call` handler fires
- **THEN** the plugin SHALL reconstruct the full file content, call `review()`, and block if rejected

#### Scenario: Amp plugin manages statusline state
- **WHEN** the Amp plugin processes a review
- **THEN** it SHALL call `neph("set", "amp_active", "true")` and `neph("unset", "amp_active")` around the review

### Requirement: OpenCode custom tool override
neph.nvim SHALL include an OpenCode custom tool at `tools/opencode/neph-write.ts` that overrides the built-in `write` and `edit` tools to route file mutations through `neph review` using the shared `lib/neph-run.ts` module.

#### Scenario: OpenCode write overridden
- **WHEN** OpenCode invokes the `write` tool and the custom override is installed
- **THEN** the override SHALL call `review(filePath, content)` from `lib/neph-run.ts` before writing to disk

#### Scenario: OpenCode edit overridden
- **WHEN** OpenCode invokes the `edit` tool and the custom override is installed
- **THEN** the override SHALL reconstruct the full file content, call `review()`, and block if rejected

#### Scenario: OpenCode adapter manages statusline state
- **WHEN** the OpenCode adapter processes a review
- **THEN** it SHALL call `neph("set", "opencode_active", "true")` and `neph("unset", "opencode_active")` around the review

### Requirement: TypeScript adapters use shared lib
Both `tools/amp/neph-plugin.ts` and `tools/opencode/neph-write.ts` SHALL import `nephRun`, `review`, and `neph` from `tools/lib/neph-run.ts` rather than defining these functions inline.

#### Scenario: No duplicated nephRun logic
- **WHEN** the amp and opencode adapter source files are inspected
- **THEN** neither SHALL contain inline definitions of `nephRun`, `review`, or fire-and-forget `neph`
- **AND** both SHALL import from `../lib/neph-run`

### Requirement: TypeScript adapters have package.json
Each TypeScript adapter directory (`tools/amp/`, `tools/opencode/`) SHALL have a `package.json` with required dependencies for compilation and testing.

#### Scenario: Package files exist
- **WHEN** `tools/amp/package.json` and `tools/opencode/package.json` are inspected
- **THEN** they SHALL exist and declare required dependencies
