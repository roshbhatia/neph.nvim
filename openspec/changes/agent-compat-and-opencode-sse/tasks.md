## 1. Cupcake health check

- [ ] 1.1 In `health.lua`, add `check_deps()` (or extend `check_agents()`): iterate registered agents, collect unique `integration_group` values, warn if any == `"harness"` and `vim.fn.executable("cupcake") == 0`
- [ ] 1.2 Include the affected agent names in the warning message so the user knows which agents need Cupcake
- [ ] 1.3 Add test: `health_spec.lua` — cupcake check fires when a harness agent is registered and `cupcake` mock is absent

## 2. Remove incorrect cursor tools dst

- [ ] 2.1 Delete the `tools` field from `lua/neph/agents/cursor.lua`
- [ ] 2.2 Add a comment referencing `neph integration toggle cursor` as the canonical install path
- [ ] 2.3 Update any tests that assert cursor agent tools shape

## 3. Fix dist_is_current stale detection

- [ ] 3.1 In `lua/neph/internal/tools.lua` `dist_is_current()`: after scanning `pkg_dir/src/` and finding zero `.ts` files, fall back to scanning `pkg_dir/` root level for `.ts` files
- [ ] 3.2 Add test: package with no `src/` dir (amp-like) returns `"stale"` when root `.ts` file is newer than dist artifact
- [ ] 3.3 Add test: package with no `src/` dir returns `"current"` when dist artifact is newer
- [ ] 3.4 Verify `health.lua` `check_build` entries for amp and pi now detect staleness correctly

## 4. Fix order-dependent test failures

- [ ] 4.1 Run `PlenaryBustedDirectory` with `--seed` variations to isolate which spec pair triggers the 3 failures
- [ ] 4.2 Identify the shared module state (likely `neph.api.review`, `neph.internal.gate`, or `neph.internal.review_queue`)
- [ ] 4.3 Add `_reset()` call or `package.loaded[...] = nil` in the offending spec's `after_each`
- [ ] 4.4 Confirm full suite runs with zero failures across 3 consecutive runs

## 5. opencode neph-cli integration entry

- [ ] 5.1 Add opencode entry to `INTEGRATIONS` in `tools/neph-cli/src/integration.ts`:
  - `name: "opencode"`, `label: "OpenCode"`, `requiresCupcake: true`
  - Status check: verify `.cupcake/policies/opencode` exists in `process.cwd()`
- [ ] 5.2 Ensure `neph integration status` output includes opencode row
- [ ] 5.3 Add test in neph-cli test suite: opencode status reported correctly when policy file present/absent
- [ ] 5.4 Build and verify `neph integration status` output locally

## 6. opencode SSE subscription and permission bridge

### 6.1 Server discovery
- [ ] 6.1.1 Create `lua/neph/internal/opencode_sse.lua` with `M.discover_port()`: run `pgrep -f "opencode .*--port"` via `vim.fn.system`, parse port from argv, validate with `GET /session` via `vim.fn.jobstart`
- [ ] 6.1.2 Cache discovered port for the session; re-discover on reconnect

### 6.2 SSE subscriber
- [ ] 6.2.1 `M.subscribe(port, on_event)`: launch `curl -N http://localhost:<port>/event` as a jobstart, parse SSE lines (`data: <json>` → decode → call `on_event(type, data)`)
- [ ] 6.2.2 Implement reconnect: on job exit with code != 0, retry after 2s up to 5 times
- [ ] 6.2.3 `M.unsubscribe()`: stop the curl job, clear reconnect timer
- [ ] 6.2.4 `M.is_subscribed()`: returns bool

### 6.3 Permission bridge review provider
- [ ] 6.3.1 Create `lua/neph/reviewers/opencode_permission.lua`:
  - `M.is_enabled_for(agent)` returns true only when agent == `"opencode"` and SSE is subscribed
  - On `permission.asked` with `permission == "edit"`: extract diff from `event.properties.metadata.diff`, derive `path` from `event.properties.metadata.path`, enqueue a neph review
  - After review decision: POST `{ decision: "once" | "reject" }` to `http://localhost:<port>/permission/<id>/reply` via `vim.fn.jobstart({"curl", "-s", "-X", "POST", ...})`
- [ ] 6.3.2 On `file.edited` SSE event: run `vim.schedule(function() vim.cmd("checktime") end)` instead of fs_watcher for opencode-originated writes

### 6.4 Wiring
- [ ] 6.4.1 In `lua/neph/agents/opencode.lua`: add `--port <N>` to launch args (port sourced from `opencode_sse.discover_port()` or auto-assigned), set `integration_group = "opencode_sse"` (new group)
- [ ] 6.4.2 In `lua/neph/internal/integration.lua`: register `opencode_sse` integration group with `review_provider = "opencode_permission"`, `policy_engine = "noop"`
- [ ] 6.4.3 In `lua/neph/internal/session.lua`: on agent start for opencode, call `opencode_sse.subscribe()`; on agent stop, call `opencode_sse.unsubscribe()`
- [ ] 6.4.4 Fallback: when opencode is running without `--port` (no HTTP server), fall back to existing harness/Cupcake path

### 6.5 Tests
- [ ] 6.5.1 `tests/internal/opencode_sse_spec.lua`: SSE line parser, server discovery with mock pgrep output, reconnect logic
- [ ] 6.5.2 `tests/reviewers/opencode_permission_spec.lua`: permission bridge enqueues review on `permission.asked`; accept posts correct reply; reject posts correct reply; `file.edited` triggers checktime
- [ ] 6.5.3 Integration test: mock opencode HTTP server, verify full permission.asked → neph review → POST reply round-trip
