---@type neph.AgentDef
--- OpenCode agent operated through opencode.nvim.
---
--- Requires the `nickjvandyke/opencode.nvim` plugin to be installed
--- alongside neph. opencode.nvim manages the HTTP/SSE transport, prompt
--- input UI, and context system; neph provides the picker, gate, review
--- queue, and history layer on top.
return {
  name = "opencode",
  label = "OpenCode",
  icon = "",
  cmd = "opencode",
  type = "peer",
  peer = {
    kind = "opencode",
    -- Listen to opencode.nvim's User OpencodeEvent:permission.asked autocmd
    -- and route file-edit permissions through neph's review queue. The peer
    -- adapter also suppresses opencode.nvim's native diff tab.
    intercept_permissions = true,
  },
  -- "hook" integration group: review_provider=vimdiff with policy_engine=noop
  -- and formatter=noop. Gives neph's review UI for permission interception
  -- under gate=normal/hold; bypass mode short-circuits before the UI opens.
  integration_group = "hook",
  -- Peer agents default to the floating popup UI. See claude-peer.lua.
  review_style = "popup",
}
