## REMOVED Requirements

### Requirement: NephTools user command with subcommands
**Reason**: Integration management is moved to the neph CLI to keep it editor-agnostic and composable.
**Migration**: Use `neph integration toggle` and `neph integration status` instead of `:NephTools`.
