## Context

OpenCode expects global plugins to be in a plural `plugins/` directory. The initial implementation of the `opencode-native-ui` bridge used the singular `plugin/` directory in the agent definition's symlink configuration.

## Goals / Non-Goals

**Goals:**
- Correct the plugin directory path for OpenCode to ensure the Neph companion bridge is loaded.

**Non-Goals:**
- Changing the plugin logic or any other agent configuration.

## Decisions

**1. Pluralize the Directory Path:**
Update the symlink target in `lua/neph/agents/opencode.lua` from `~/.config/opencode/plugin/neph-companion.js` to `~/.config/opencode/plugins/neph-companion.js`.

## Risks / Trade-offs

- **[Risk] Multiple symlinks**: If both singular and plural directories exist, it might cause confusion, but OpenCode specifically looks for the plural one for global plugins.
  - **Mitigation**: Standardize on the plural path as required by OpenCode documentation.
