## MODIFIED Requirements

### Requirement: neph-cli is agent-independent

The neph-cli build and symlink SHALL remain in `tools.lua` as universal infrastructure not associated with any agent. The symlink to `~/.local/bin/neph` SHALL only be created when explicitly requested via `:NephTools install all` or `:NephTools install neph-cli`. The automatic `install_async()` at startup SHALL build neph-cli but SHALL skip the symlink creation. Tool installation SHALL additionally handle Cupcake policy deployment and Pi harness installation.

#### Scenario: neph-cli built but not symlinked at startup
- **WHEN** `tools.install_async()` runs at Neovim startup
- **THEN** `tools/neph-cli/dist/index.js` SHALL be built if sources are newer than artifact
- **AND** the symlink to `~/.local/bin/neph` SHALL NOT be created automatically

#### Scenario: Cupcake policies deployed at startup
- **WHEN** `tools.install_async()` runs
- **AND** `cupcake` CLI is available on PATH
- **THEN** neph's Rego policy files SHALL be deployed to `.cupcake/policies/neph/`
- **AND** the `neph_review` signal SHALL be configured in `.cupcake/rulebook.yml`

#### Scenario: Pi harness built and installed
- **WHEN** `tools.install_async()` runs
- **AND** Pi agent is configured
- **THEN** the Pi Cupcake harness SHALL be built from `tools/pi/`
- **AND** symlinked to `~/.pi/agent/extensions/nvim/`

#### Scenario: Hook configs generated for Claude and Gemini
- **WHEN** `tools.install_async()` runs
- **THEN** `.claude/settings.json` SHALL be updated with PreToolUse hook pointing to `neph-cli review --agent claude`
- **AND** `.gemini/settings.json` SHALL be updated with BeforeTool hook pointing to `neph-cli review --agent gemini`
- **AND** existing non-neph hook entries SHALL be preserved

## REMOVED Requirements

### Requirement: Gemini companion sidecar installation
**Reason**: Gemini companion sidecar (`tools/gemini/`) replaced by native Gemini CLI hooks via Cupcake or direct hook config.
**Migration**: Remove Gemini companion build and symlink steps from tools.lua. Gemini integration now uses `.gemini/settings.json` BeforeTool hook.

### Requirement: NephClient SDK installation
**Reason**: NephClient SDK (`tools/lib/neph-client.ts`) removed. Extension agents no longer exist.
**Migration**: Pi uses Cupcake harness. No shared SDK to install.
