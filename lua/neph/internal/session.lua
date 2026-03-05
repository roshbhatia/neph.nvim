---@mod neph.session Session management
---@brief [[
--- Manages open agent terminal sessions.  Auto-detects the best backend:
---   1. SSH connections → always native (snacks.nvim splits)
---   2. WezTerm available → wezterm pane backend
---   3. Fallback → native backend
---@brief ]]

local M = {}

---@type table  Backend module (neph.backends.wezterm or neph.backends.native)
local backend = nil
---@type neph.Config
local config = {}
---@type table<string, table>  termname → term_data
local terminals = {}
---@type string|nil
local active_terminal = nil
---@type integer|nil
local augroup = nil

-- ---------------------------------------------------------------------------
-- Backend detection
-- ---------------------------------------------------------------------------

---@return "snacks"|"wezterm"|"tmux"|"zellij"
local function detect_backend()
  return config.multiplexer or "snacks"
end

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------

---@param opts neph.Config
function M.setup(opts)
  config = opts or {}
  config.env = config.env or {}

  local btype = detect_backend()
  if btype == "wezterm" then
    backend = require("neph.internal.backends.wezterm")
  elseif btype == "tmux" then
    -- Stub: warns and falls back to snacks
    require("neph.internal.backends.tmux").setup(config)
    backend = require("neph.internal.backends.native")
  elseif btype == "zellij" then
    -- Stub: warns and falls back to snacks
    require("neph.internal.backends.zellij").setup(config)
    backend = require("neph.internal.backends.native")
  else
    -- "snacks" (default) and any unrecognised value
    backend = require("neph.internal.backends.native")
  end
  backend.setup(config)

  if not augroup then
    augroup = vim.api.nvim_create_augroup("NephSession", { clear = true })

    -- Periodically check pane health
    vim.api.nvim_create_autocmd("CursorHold", {
      group = augroup,
      callback = function()
        for name, td in pairs(terminals) do
          if not backend.is_visible(td) then
            td.pane_id = nil
            td.win = nil
            td.stale_since = os.time()
            if active_terminal == name then
              active_terminal = nil
            end
          elseif td.stale_since then
            td.stale_since = nil
          end
        end
      end,
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = augroup,
      callback = function()
        backend.cleanup_all(terminals)
      end,
    })
  end
end

-- ---------------------------------------------------------------------------
-- Core operations
-- ---------------------------------------------------------------------------

function M.open(termname)
  local agent = require("neph.internal.agents").get_by_name(termname)
  if not agent then
    vim.notify("Neph: unknown agent – " .. termname, vim.log.levels.ERROR)
    return
  end

  if terminals[termname] and backend.is_visible(terminals[termname]) then
    M.focus(termname)
    return
  end

  local cwd = vim.fn.getcwd()

  -- Build agent_config expected by backends: { cmd, args, full_cmd }
  local agent_config = {
    cmd = agent.full_cmd or agent.cmd,
    args = agent.args or {},
    full_cmd = agent.full_cmd or agent.cmd,
  }

  local td = backend.open(termname, agent_config, cwd)
  if td then
    terminals[termname] = td
    active_terminal = termname
  end
end

function M.toggle(termname)
  local td = terminals[termname]
  if td and backend and backend.is_visible(td) then
    M.focus(termname)
  else
    M.open(termname)
  end
end

function M.focus(termname)
  local td = terminals[termname]
  if not td or not backend then
    return
  end
  if not backend.is_visible(td) then
    td.pane_id = nil
    td.win = nil
    M.open(termname)
    return
  end
  if not backend.focus(td) then
    td.pane_id = nil
    td.win = nil
    M.open(termname)
    return
  end
  active_terminal = termname
end

function M.hide(termname)
  local td = terminals[termname]
  if not td or not backend then
    return
  end
  backend.hide(td)
  terminals[termname] = nil
  if active_terminal == termname then
    active_terminal = nil
  end
end

function M.activate(termname)
  local td = terminals[termname]
  if not td or not backend or not backend.is_visible(td) then
    M.open(termname)
  else
    M.focus(termname)
  end
  active_terminal = termname
end

function M.kill_session(termname)
  local td = terminals[termname]
  if td and backend then
    backend.kill(td)
  end
  terminals[termname] = nil
  if active_terminal == termname then
    active_terminal = nil
  end
end

function M.send(termname, text, opts)
  opts = opts or {}
  local td = terminals[termname]
  if not td then
    return
  end

  if td.pane_id then
    vim.fn.system(
      string.format("wezterm cli send-text --pane-id %d --no-paste %s", td.pane_id, vim.fn.shellescape(text))
    )
    if opts.submit then
      vim.fn.system(string.format("wezterm cli send-text --pane-id %d --no-paste '\n'", td.pane_id))
    end
  elseif td.term then
    td.term:send(text)
    if opts.submit then
      td.term:send("\n")
    end
  end
end

function M.ensure_active_and_send(text)
  if not active_terminal then
    vim.notify("Neph: no active terminal – pick one with <leader>jj", vim.log.levels.WARN)
    return
  end
  if not M.exists(active_terminal) then
    M.open(active_terminal)
    M.focus(active_terminal)
    local retries = 20
    for _ = 1, retries do
      if M.exists(active_terminal) then
        M.send(active_terminal, text, { submit = true })
        return
      end
      vim.fn.system("sleep 0.05")
    end
    vim.notify("Neph: terminal failed to become ready", vim.log.levels.ERROR)
  else
    M.focus(active_terminal)
    M.send(active_terminal, text, { submit = true })
  end
end

-- ---------------------------------------------------------------------------
-- Query helpers
-- ---------------------------------------------------------------------------

function M.get_active()
  return active_terminal
end
function M.set_active(n)
  if terminals[n] then
    active_terminal = n
  end
end

function M.is_visible(termname)
  local td = terminals[termname]
  return td and backend and backend.is_visible(td) or false
end

function M.is_tracked(termname)
  local td = terminals[termname]
  if not td then
    return false
  end
  return backend and backend.is_visible(td) or false
end

function M.exists(termname)
  return M.is_visible(termname)
end

function M.get_info(termname)
  local td = terminals[termname]
  if not td or not backend then
    return nil
  end
  return {
    name = termname,
    visible = backend.is_visible(td),
    pane_id = td.pane_id,
    cmd = td.cmd,
    cwd = td.cwd,
    win = td.win,
    buf = td.buf,
  }
end

function M.get_all()
  local result = {}
  for name in pairs(terminals) do
    result[name] = M.get_info(name)
  end
  return result
end

return M
