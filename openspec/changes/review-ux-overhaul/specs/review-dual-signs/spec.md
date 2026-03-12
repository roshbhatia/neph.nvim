## REMOVED Requirements

### Requirement: Signs placed on both left and right buffers

**Reason:** Replaced by left-side-only signs. Right-side signs were redundant with Neovim's native diff highlighting (DiffAdd, DiffChange, DiffText, DiffDelete) and added visual noise. The inverse sign semantics (✗ on left for accept) were confusing.

**Migration:** Signs are now placed only on the left buffer. The sign semantics are simplified: `✓` = accepted, `✗` = rejected, `→` = current undecided. All right-side sign tracking (`right_sign_ids`) is removed.

### Requirement: Right buffer tracks separate sign IDs

**Reason:** No longer needed since signs are only placed on the left buffer.

**Migration:** `ui_state.right_sign_ids` is removed from the state object. `ui_state.left_sign_ids` remains as `ui_state.sign_ids`.
