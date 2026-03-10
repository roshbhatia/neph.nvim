## 1. Neovim UI RPC Layer

- [x] 1.1 Create `lua/neph/api/ui.lua` with a `notify(params)` function that calls `vim.notify`
- [x] 1.2 Implement `select(params)` in `lua/neph/api/ui.lua` to call `vim.ui.select` and send a `neph:ui_response` notification back via `channel_id`
- [x] 1.3 Implement `input(params)` in `lua/neph/api/ui.lua` to call `vim.ui.input` and send a `neph:ui_response` notification back via `channel_id`
- [x] 1.4 Update `lua/neph/rpc.lua` to dispatch `ui.select`, `ui.input`, and `ui.notify` to the new module
- [x] 1.5 Update `protocol.json` with the new UI methods

## 2. NephClient Updates

- [x] 2.1 Update `tools/lib/neph-client.ts` to manage pending async RPC requests (e.g., a map of `request_id` to promise resolvers)
- [x] 2.2 Refactor `NephClient.review` to use this async request mapping instead of the current synchronous/fire-and-forget mechanism, listening for `neph:review_done`
- [x] 2.3 Implement `NephClient.uiNotify(message, type)` using the `ui.notify` RPC call
- [x] 2.4 Implement `NephClient.uiSelect(title, options)` using the pending async requests pattern and `ui.select` RPC
- [x] 2.5 Implement `NephClient.uiInput(title, defaultText)` using the pending async requests pattern and `ui.input` RPC

## 3. Pi Extension Integration

- [x] 3.1 Update `tools/pi/pi.ts` to intercept `ctx.ui` in the `session_start` event
- [x] 3.2 Override `ctx.ui.select` to await `neph.uiSelect`
- [x] 3.3 Override `ctx.ui.input` to await `neph.uiInput`
- [x] 3.4 Override `ctx.ui.confirm` to await `neph.uiSelect` with Yes/No options
- [x] 3.5 Override `ctx.ui.notify` to call `neph.uiNotify`

## 4. Testing & Validation

- [x] 4.1 Add tests to `tools/pi/tests/` to verify `ctx.ui` methods properly invoke `NephClient`
- [x] 4.2 Add integration tests in `tools/neph-cli/tests/` for the new UI RPC endpoints
- [x] 4.3 Add Lua tests in `tests/rpc_spec.lua` (or new `ui_spec.lua`) to verify `vim.ui` functions are called correctly
