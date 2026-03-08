## REMOVED Requirements

### Requirement: Extension agent send_adapter SHALL deliver prompts regardless of startup timing
**Reason:** Replaced by bus registration. Extension agents register with the bus when ready. Before registration, prompts fall through to terminal send. After registration, prompts are delivered instantly via notification. No vim.g polling, no timing concerns.
**Migration:** Extension agents call `NephClient.register()` on startup. The bus handles the rest.

### Requirement: Session cleanup SHALL clear pending prompt for extension agents
**Reason:** `vim.g.neph_pending_prompt` no longer exists. The bus clears channel registrations on session kill. No pending prompt state to clean up.
**Migration:** Bus cleanup is automatic on channel disconnect or session kill.
