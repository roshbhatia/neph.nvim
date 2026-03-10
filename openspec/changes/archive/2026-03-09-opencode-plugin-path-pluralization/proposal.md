## Why

The current configuration for the OpenCode agent bridge uses the path `~/.config/opencode/plugin/`, but OpenCode expects global plugins to be located in `~/.config/opencode/plugins/` (plural). This discrepancy prevents the agent from correctly loading and initializing the Neph companion bridge plugin.

## What Changes

- Update the symlink destination for the OpenCode persistent bridge in `lua/neph/agents/opencode.lua` from `~/.config/opencode/plugin/neph-companion.js` to `~/.config/opencode/plugins/neph-companion.js`.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `opencode-native-ui`: Update the plugin installation path to match OpenCode's expectations.

## Impact

- `lua/neph/agents/opencode.lua`
- Agent installation/setup process.
