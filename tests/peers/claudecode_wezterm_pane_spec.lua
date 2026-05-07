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

    -- Stub vim.system so pane_is_alive() (which checks `wezterm cli list`)
    -- can be made to report the pane as alive or dead per-test. Default:
    -- alive — return a JSON list containing pane_id "42".
    _G.__orig_system = vim.system
    vim.system = function(cmd, _opts)
      return {
        wait = function(_self, _timeout)
          -- Default: pretend the alive-pane is in the list.
          return {
            code = 0,
            stdout = '[{"pane_id": 42, "title": "Claude"}]',
            stderr = "",
          }
        end,
      }
    end
  end)

  after_each(function()
    if _G.__orig_jobstart then
      vim.fn.jobstart = _G.__orig_jobstart
      _G.__orig_jobstart = nil
    end
    if _G.__orig_system then
      vim.system = _G.__orig_system
      _G.__orig_system = nil
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

  --- Find the most recent send-text jobstart call (we may issue other
  --- wezterm CLI invocations too — e.g. activate-pane or kill-pane in
  --- other tests, though pane_is_alive uses vim.system, not jobstart).
  local function last_send_text()
    for i = #jobstart_calls, 1, -1 do
      local c = jobstart_calls[i].cmd
      if type(c) == "table" and c[1] == "wezterm" and c[3] == "send-text" then
        return c
      end
    end
    return nil
  end

  it("M.send dispatches to wezterm cli send-text when pane_id is owned", function()
    peer._set_pane_id("42")
    peer.send(nil, "hello", { submit = true })
    local cmd = last_send_text()
    assert.is_table(cmd, "expected a wezterm cli send-text invocation")
    assert.are.equal("--pane-id", cmd[4])
    assert.are.equal("42", cmd[5])
    assert.are.equal("--no-paste", cmd[6])
    assert.are.equal("hello\r", cmd[7])
  end)

  it("M.send without submit drops the trailing \\r", function()
    peer._set_pane_id("42")
    peer.send(nil, "hi", { submit = false })
    local cmd = last_send_text()
    assert.is_table(cmd, "expected a wezterm cli send-text invocation")
    assert.are.equal("hi", cmd[7])
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
    -- Stub claudecode.terminal so drop_pane_state's close() call is a noop.
    package.loaded["claudecode.terminal"] = { close = function() end }
    peer._set_pane_id("42")
    peer.kill(nil)
    -- First wezterm jobstart should be the kill-pane call.
    local kill_cmd
    for _, c in ipairs(jobstart_calls) do
      if c.cmd[1] == "wezterm" and c.cmd[3] == "kill-pane" then
        kill_cmd = c.cmd
        break
      end
    end
    assert.is_table(kill_cmd, "expected a wezterm cli kill-pane invocation")
    assert.are.equal("42", kill_cmd[5])
    -- After kill, is_visible should report false (state cleared)
    assert.is_false(peer.is_visible(nil))
  end)

  it("M.is_visible verifies pane is alive and returns true when present", function()
    peer._set_pane_id("42")
    -- Default vim.system stub returns a JSON list including pane_id 42.
    assert.is_true(peer.is_visible(nil))
  end)

  it("M.is_visible drops state when tracked pane is gone", function()
    peer._set_pane_id("99")
    -- vim.system stub returns pane_id 42 only — 99 is not in the list,
    -- so is_visible should return false AND clear state.
    assert.is_false(peer.is_visible(nil))
  end)

  it("M.focus spawns wezterm cli activate-pane when pane_id is owned and alive", function()
    peer._set_pane_id("42")
    local ok = peer.focus(nil)
    assert.is_true(ok)
    -- Find the activate-pane invocation (other jobstarts may occur).
    local activate_cmd
    for _, c in ipairs(jobstart_calls) do
      if c.cmd[1] == "wezterm" and c.cmd[3] == "activate-pane" then
        activate_cmd = c.cmd
        break
      end
    end
    assert.is_table(activate_cmd, "expected an activate-pane invocation")
    assert.are.equal("42", activate_cmd[5])
  end)

  it("M.hide is a no-op when pane_id is owned (can't hide a wezterm pane)", function()
    peer._set_pane_id("42")
    peer.hide(nil)
    -- No jobstart calls — hide is a deliberate no-op for wezterm panes.
    assert.are.equal(0, #jobstart_calls)
  end)
end)
