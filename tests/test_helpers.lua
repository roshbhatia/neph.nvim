-- test_helpers.lua – shared helpers to reduce boilerplate across test files

local M = {}

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
