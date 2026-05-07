---@type neph.AgentDef
return {
  name = "opencode",
  label = "OpenCode",
  icon = "",
  cmd = "opencode",
  type = "hook",
  -- "hook" integration_group: review_provider=vimdiff. Without the SSE
  -- subscription, pre-write interception isn't possible; instead the
  -- fs_watcher catches opencode's writes post-fact and routes them
  -- through neph's review queue (gate=normal opens vimdiff;
  -- gate=bypass auto-accepts).
  integration_group = "hook",
}
