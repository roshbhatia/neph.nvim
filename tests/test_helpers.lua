-- test_helpers.lua – shared helpers to reduce boilerplate across test files

local M = {}

-- ---------------------------------------------------------------------------
-- Window / buffer stubs
-- ---------------------------------------------------------------------------

--- Return a minimal window-validity stub.
--- By default nvim_win_is_valid returns true for the given win_id.
--- opts:
---   valid (bool, default true)  – whether the window is considered valid
---   floating (bool, default false) – whether nvim_win_get_config reports relative ~= ""
---@param win_id integer
---@param opts? {valid?: boolean, floating?: boolean}
---@return table  # { win_id, restore() }
function M.mock_win(win_id, opts)
  opts = opts or {}
  local valid = opts.valid ~= false
  local floating = opts.floating == true

  local orig_is_valid = vim.api.nvim_win_is_valid
  local orig_get_config = vim.api.nvim_win_get_config

  vim.api.nvim_win_is_valid = function(w)
    if w == win_id then
      return valid
    end
    return orig_is_valid(w)
  end

  vim.api.nvim_win_get_config = function(w)
    if w == win_id then
      return { relative = floating and "editor" or "" }
    end
    return orig_get_config(w)
  end

  local function restore()
    vim.api.nvim_win_is_valid = orig_is_valid
    vim.api.nvim_win_get_config = orig_get_config
  end

  return { win_id = win_id, restore = restore }
end

--- Return a minimal buffer-name stub.
--- opts:
---   name (string, default "")  – value returned by nvim_buf_get_name for buf_id
---@param buf_id integer
---@param opts? {name?: string}
---@return table  # { buf_id, restore() }
function M.mock_buf(buf_id, opts)
  opts = opts or {}
  local name = opts.name or ""

  local orig_get_name = vim.api.nvim_buf_get_name

  vim.api.nvim_buf_get_name = function(b)
    if b == buf_id then
      return name
    end
    return orig_get_name(b)
  end

  local function restore()
    vim.api.nvim_buf_get_name = orig_get_name
  end

  return { buf_id = buf_id, restore = restore }
end

-- ---------------------------------------------------------------------------
-- Review request factory
-- ---------------------------------------------------------------------------

--- Build a neph.ReviewRequest table with sensible defaults.
--- Any field can be overridden.
---@param overrides? table
---@return table  # neph.ReviewRequest
function M.make_review_request(overrides)
  local uid = tostring(math.random(100000))
  return vim.tbl_extend("force", {
    request_id = "req-" .. uid,
    result_path = "/tmp/neph-test-result-" .. uid .. ".json",
    channel_id = 1,
    path = "/tmp/neph-test-file-" .. uid .. ".lua",
    content = "-- test content",
    agent = "test-agent",
    mode = "pre_write",
  }, overrides or {})
end

-- ---------------------------------------------------------------------------
-- Gate helper
-- ---------------------------------------------------------------------------

--- Run fn with the gate module set to the given state, then restore it.
--- Freshly requires neph.internal.gate so the caller does not need to manage
--- package.loaded themselves.
---@param state "normal"|"hold"|"bypass"
---@param fn fun(gate: table)
function M.with_gate(state, fn)
  package.loaded["neph.internal.gate"] = nil
  local gate = require("neph.internal.gate")
  if state ~= "normal" then
    gate.set(state)
  end
  local ok, err = pcall(fn, gate)
  -- Always restore to normal so subsequent tests start clean
  package.loaded["neph.internal.gate"] = nil
  if not ok then
    error(err, 2)
  end
end

-- ---------------------------------------------------------------------------
-- vim.notify capture
-- ---------------------------------------------------------------------------

--- Replace vim.notify with a recording stub.
--- Returns a list that accumulates every {msg, level} pair and a restore()
--- function that must be called in after_each / cleanup.
---@return table[], fun()  # notifications list, restore function
function M.capture_notifications()
  local list = {}
  local orig_notify = vim.notify

  vim.notify = function(msg, level, opts)
    table.insert(list, { msg = msg, level = level, opts = opts })
  end

  local function restore()
    vim.notify = orig_notify
  end

  return list, restore
end

--- Assert that at least one captured notification matches level and pattern.
---@param list table[]         # list returned by capture_notifications()
---@param level integer        # e.g. vim.log.levels.WARN
---@param pattern string       # Lua pattern matched against msg
function M.assert_notify(list, level, pattern)
  for _, n in ipairs(list) do
    if n.level == level and n.msg:find(pattern) then
      return
    end
  end
  local dump = {}
  for _, n in ipairs(list) do
    dump[#dump + 1] = string.format("  [level=%s] %q", tostring(n.level), tostring(n.msg))
  end
  error(
    string.format(
      "assert_notify: no notification matched level=%s pattern=%q\nCaptured:\n%s",
      tostring(level),
      pattern,
      table.concat(dump, "\n")
    ),
    2
  )
end

-- ---------------------------------------------------------------------------
-- Agent / backend factories (pre-existing)
-- ---------------------------------------------------------------------------

--- Create a valid agent config table (for backend tests).
---@param overrides? table
---@return table
function M.make_agent_config(overrides)
  return vim.tbl_extend("force", {
    cmd = "echo",
    args = {},
    full_cmd = "echo hello",
    env = { MY_VAR = "test" },
  }, overrides or {})
end

--- Create a stub backend with all required methods, optionally overriding any.
---@param overrides? table
---@return table
function M.make_stub_backend(overrides)
  local base = {
    setup = function() end,
    open = function(_, agent_cfg, _)
      return { pane_id = 999, cmd = agent_cfg.cmd, cwd = "/tmp", name = "stub", ready = true }
    end,
    focus = function()
      return true
    end,
    hide = function(td)
      td.pane_id = nil
    end,
    is_visible = function(td)
      return td ~= nil and td.pane_id ~= nil
    end,
    kill = function(td)
      td.pane_id = nil
    end,
    cleanup_all = function() end,
    send = function() end,
  }
  return vim.tbl_extend("force", base, overrides or {})
end

--- Create a valid agent definition that passes contract validation.
---@param overrides? table
---@return table
function M.make_valid_agent(overrides)
  return vim.tbl_extend("force", {
    name = "test",
    label = "Test",
    icon = " ",
    cmd = "ls",
    args = {},
  }, overrides or {})
end

--- Save and restore globals commonly mocked in tests.
--- Returns save() and restore() functions.
---@return fun(), fun()
function M.save_and_restore_globals()
  local saved = {}

  local function save()
    saved.system = vim.fn.system
    saved.jobstart = vim.fn.jobstart
    saved.chansend = vim.fn.chansend
    saved.chanclose = vim.fn.chanclose
    saved.executable = vim.fn.executable
    saved.shellescape = vim.fn.shellescape
    saved.WEZTERM_PANE = vim.env.WEZTERM_PANE
    saved.ZELLIJ = vim.env.ZELLIJ
    saved.ZELLIJ_SESSION_NAME = vim.env.ZELLIJ_SESSION_NAME
    saved.Snacks = rawget(_G, "Snacks")
  end

  local function restore()
    vim.fn.system = saved.system
    vim.fn.jobstart = saved.jobstart
    vim.fn.chansend = saved.chansend
    vim.fn.chanclose = saved.chanclose
    vim.fn.executable = saved.executable
    vim.fn.shellescape = saved.shellescape
    vim.env.WEZTERM_PANE = saved.WEZTERM_PANE
    vim.env.ZELLIJ = saved.ZELLIJ
    vim.env.ZELLIJ_SESSION_NAME = saved.ZELLIJ_SESSION_NAME
    if saved.Snacks then
      _G.Snacks = saved.Snacks
    else
      _G.Snacks = nil
    end
  end

  return save, restore
end

return M
