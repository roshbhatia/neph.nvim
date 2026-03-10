## 1. Fix Plugin Path

- [x] 1.1 Update `lua/neph/agents/opencode.lua` to change `plugin` to `plugins` in the symlink destination.

## 2. Validation

- [x] 2.1 Verify the path change in `opencode.lua`.
- [x] 2.2 Verify that `amp.lua` also uses plural `plugins/` (it already does, but good to check).
