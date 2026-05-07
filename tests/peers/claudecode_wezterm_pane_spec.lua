---@diagnostic disable: undefined-global
-- Verifies the claudecode peer's wezterm-pane integration:
--   * wezterm_pane_cmd returns expected argv shape and registers cleanup,
--   * M.send dispatches to wezterm cli send-text when pane_id is set,
--   * M.send falls back to bufnr chansend when pane_id is nil,
--   * M.kill spawns wezterm cli kill-pane and clears pane_id,
--   * M.is_visible returns true when pane_id is owned (no shell-out),
--   * M.focus spawns wezterm cli activate-pane.

describe("neph.peers.claudecode wezterm pane integration", function()
  local peer
  local jobstart_calls

  before_each(function()
    package.loaded["neph.peers.claudecode"] = nil
    package.loaded["claudecode"] = nil
    package.loaded["claudecode.diff"] = nil
    package.loaded["claudecode.terminal"] = nil

    package.loaded["claudecode"] = { stop = function() end }
    peer = require("neph.peers.claudecode")
    if peer._reset then
      peer._reset()
    end

    -- Capture jobstart invocations for assertion.
    jobstart_calls = {}
    _G.__orig_jobstart = vim.fn.jobstart
    vim.fn.jobstart = function(cmd, opts)
      table.insert(jobstart_calls, { cmd = cmd, opts = opts })
      return 1 -- fake job id
    end
  end)

  after_each(function()
    if _G.__orig_jobstart then
      vim.fn.jobstart = _G.__orig_jobstart
      _G.__orig_jobstart = nil
    end
    if peer and peer._reset then
      peer._reset()
    end
  end)

  it("wezterm_pane_cmd returns sh -c argv with split-pane and stdout redirect", function()
    local argv = peer.wezterm_pane_cmd("claude --foo", {})
    assert.is_table(argv)
    assert.are.equal("sh", argv[1])
    assert.are.equal("-c", argv[2])
    assert.is_string(argv[3])
    assert.truthy(argv[3]:find("wezterm cli split-pane --right", 1, true), "missing split-pane invocation")
    assert.truthy(argv[3]:find("claude --foo", 1, true), "command not embedded")
    assert.truthy(argv[3]:find(">", 1, true), "missing stdout redirect for pane_id capture")
  end)

  it("wezterm_pane_cmd registers a VimLeavePre autocmd in NephClaudecodeWezterm augroup", function()
    peer.wezterm_pane_cmd("claude", {})
    local aus = vim.api.nvim_get_autocmds({ group = "NephClaudecodeWezterm", event = "VimLeavePre" })
    assert.is_true(#aus >= 1, "expected at least one VimLeavePre autocmd")
  end)

  it("M.send dispatches to wezterm cli send-text when pane_id is owned", function()
    peer._set_pane_id("42")
    peer.send(nil, "hello", { submit = true })
    assert.are.equal(1, #jobstart_calls)
    local cmd = jobstart_calls[1].cmd
    assert.are.equal("wezterm", cmd[1])
    assert.are.equal("cli", cmd[2])
    assert.are.equal("send-text", cmd[3])
    assert.are.equal("--pane-id", cmd[4])
    assert.are.equal("42", cmd[5])
    assert.are.equal("--no-paste", cmd[6])
    assert.are.equal("hello\r", cmd[7])
  end)

  it("M.send without submit drops the trailing \\r", function()
    peer._set_pane_id("42")
    peer.send(nil, "hi", { submit = false })
    assert.are.equal(1, #jobstart_calls)
    assert.are.equal("hi", jobstart_calls[1].cmd[7])
  end)

  it("M.send with no pane_id does NOT call wezterm cli", function()
    peer._set_pane_id(nil)
    -- claudecode.terminal isn't fully stubbed; M.send should bail at
    -- get_active_terminal_bufnr and emit a warn — but importantly it must
    -- NOT shell out to wezterm.
    peer.send(nil, "hello", { submit = true })
    for _, c in ipairs(jobstart_calls) do
      assert.are_not.equal("wezterm", c.cmd[1])
    end
  end)

  it("M.kill spawns wezterm cli kill-pane and clears pane_id", function()
    peer._set_pane_id("42")
    peer.kill(nil)
    -- First jobstart should be the kill-pane call.
    assert.is_true(#jobstart_calls >= 1)
    local kill = jobstart_calls[1].cmd
    assert.are.equal("wezterm", kill[1])
    assert.are.equal("kill-pane", kill[3])
    assert.are.equal("42", kill[5])
    -- After kill, is_visible should report false (pane_id cleared, claudecode unstubbed)
    assert.is_false(peer.is_visible(nil))
  end)

  it("M.is_visible returns true when pane_id is owned without shelling out", function()
    peer._set_pane_id("42")
    assert.is_true(peer.is_visible(nil))
    -- Crucially, no shell-out to wezterm cli list:
    for _, c in ipairs(jobstart_calls) do
      assert.are_not.equal("list", c.cmd[3])
    end
  end)

  it("M.focus spawns wezterm cli activate-pane when pane_id is owned", function()
    peer._set_pane_id("42")
    local ok = peer.focus(nil)
    assert.is_true(ok)
    assert.is_true(#jobstart_calls >= 1)
    local cmd = jobstart_calls[1].cmd
    assert.are.equal("activate-pane", cmd[3])
    assert.are.equal("42", cmd[5])
  end)

  it("M.hide is a no-op when pane_id is owned (can't hide a wezterm pane)", function()
    peer._set_pane_id("42")
    peer.hide(nil)
    -- No jobstart calls — hide is a deliberate no-op for wezterm panes.
    assert.are.equal(0, #jobstart_calls)
  end)
end)
