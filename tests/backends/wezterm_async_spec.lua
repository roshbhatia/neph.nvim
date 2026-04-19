---@diagnostic disable: undefined-global
-- wezterm_async_spec.lua – verify that activate_pane / kill_pane are fire-and-forget
-- (vim.fn.jobstart) rather than blocking (vim.fn.system).

local function reset_wezterm()
  package.loaded["neph.backends.wezterm"] = nil
  package.loaded["neph.internal.channel"] = nil
end

describe("neph.backends.wezterm non-blocking helpers", function()
  local orig_jobstart
  local jobstart_calls

  before_each(function()
    reset_wezterm()
    orig_jobstart = vim.fn.jobstart
    jobstart_calls = {}
    vim.fn.jobstart = function(cmd, opts)
      table.insert(jobstart_calls, { cmd = cmd, opts = opts })
      return 1
    end
    -- Stub channel so the module loads cleanly
    package.loaded["neph.internal.channel"] = { socket_path = function() return "" end }
    vim.env.WEZTERM_PANE = "100"
  end)

  after_each(function()
    vim.fn.jobstart = orig_jobstart
    vim.env.WEZTERM_PANE = nil
    reset_wezterm()
  end)

  local function cmd_str(call)
    if type(call.cmd) == "table" then
      return table.concat(call.cmd, " ")
    end
    return tostring(call.cmd)
  end

  local function any_call_matches(patterns)
    for _, call in ipairs(jobstart_calls) do
      local s = cmd_str(call)
      local all = true
      for _, p in ipairs(patterns) do
        if not s:find(p) then
          all = false
          break
        end
      end
      if all then
        return true
      end
    end
    return false
  end

  it("focus() dispatches activate-pane via jobstart (non-blocking)", function()
    local wezterm = require("neph.backends.wezterm")
    wezterm.setup({})

    local td = { pane_id = 42, _killed = false }
    wezterm.focus(td)

    assert.is_true(
      any_call_matches({ "activate%-pane", "42" }),
      "Expected jobstart call with 'activate-pane --pane-id 42'"
    )
  end)

  it("kill() dispatches kill-pane via jobstart (non-blocking)", function()
    local wezterm = require("neph.backends.wezterm")
    wezterm.setup({})

    local td = { pane_id = 55, _killed = false }
    wezterm.kill(td)

    assert.is_true(
      any_call_matches({ "kill%-pane", "55" }),
      "Expected jobstart call with 'kill-pane --pane-id 55'"
    )
  end)

  it("hide() dispatches kill-pane via jobstart (non-blocking)", function()
    local wezterm = require("neph.backends.wezterm")
    wezterm.setup({})

    local td = { pane_id = 77, _killed = false, ready_timer = nil }
    wezterm.hide(td)

    assert.is_true(
      any_call_matches({ "kill%-pane", "77" }),
      "Expected jobstart call with 'kill-pane --pane-id 77'"
    )
  end)

  it("focus() never calls vim.fn.system (activate-pane must not block)", function()
    local system_cmds = {}
    local orig_system = vim.fn.system
    vim.fn.system = function(cmd)
      table.insert(system_cmds, cmd)
      return orig_system(cmd)
    end

    local wezterm = require("neph.backends.wezterm")
    wezterm.setup({})

    local td = { pane_id = 88, _killed = false }
    wezterm.focus(td)

    vim.fn.system = orig_system

    for _, cmd in ipairs(system_cmds) do
      local s = type(cmd) == "table" and table.concat(cmd, " ") or tostring(cmd)
      assert.is_nil(
        s:find("activate%-pane"),
        "focus() must not call vim.fn.system for activate-pane (would block the event loop)"
      )
    end
  end)
end)
