## ADDED Requirements

### Requirement: OpenCode plugin installation path
The OpenCode persistent bridge plugin SHALL be installed to the plural `plugins/` directory in the OpenCode configuration root.

#### Scenario: Verify plugin path
- **WHEN** the OpenCode agent is installed or updated
- **THEN** the Neph companion bridge SHALL be symlinked to `~/.config/opencode/plugins/neph-companion.js`
