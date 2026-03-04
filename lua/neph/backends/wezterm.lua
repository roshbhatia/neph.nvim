---@mod neph.backends.wezterm WezTerm pane backend
---@brief [[
--- Spawns AI agent terminals as WezTerm split-panes to the right of the
--- current Neovim pane.  Requires WEZTERM_PANE env var and `wezterm` CLI.
---@brief ]]

local M = {}
local config = {}
local parent_pane_id = nil
---@type table<number,number>
local pane_errors = {}

local function get_current_pane()
  return tonumber(vim.env.WEZTERM_PANE)
end

local function cmd_exists(cmd)
  local r = vim.fn.system(string.format("command -v %s >/dev/null 2>&1 && echo ok || echo fail", cmd))
  return vim.trim(r) == "ok"
end

local function list_panes()
  local r = vim.fn.system("wezterm cli list --format json 2>/dev/null")
  if vim.v.shell_error ~= 0 then return nil end
  local ok, panes = pcall(vim.fn.json_decode, r)
  return ok and panes or nil
end

local function get_pane_info(pane_id)
  if not pane_id then return nil end
  local panes = list_panes()
  if not panes then return nil end
  for _, p in ipairs(panes) do
    if p.pane_id == pane_id then return p end
  end
  return nil
end

local function pane_exists(pane_id)
  local info = get_pane_info(pane_id)
  if not info then return false end
  local parent = get_pane_info(parent_pane_id)
  if not parent then return true end
  return info.window_id == parent.window_id and info.tab_id == parent.tab_id
end

local function wait_for_pane(pane_id, retries)
  for _ = 1, (retries or 5) do
    if get_pane_info(pane_id) then return true end
    vim.fn.system("sleep 0.1")
  end
  return false
end

local function activate_pane(pane_id)
  vim.fn.system(string.format("wezterm cli activate-pane --pane-id %d 2>/dev/null", pane_id))
  return vim.v.shell_error == 0
end

local function kill_pane(pane_id)
  vim.fn.system(string.format("wezterm cli kill-pane --pane-id %d 2>/dev/null", pane_id))
  return vim.v.shell_error == 0
end

-- ---------------------------------------------------------------------------

function M.setup(opts)
  config = opts or {}
  parent_pane_id = get_current_pane()
  if not parent_pane_id then
    vim.notify("Neph/wezterm: WEZTERM_PANE not set – falling back to native", vim.log.levels.WARN)
  end
end

function M.open(termname, agent_config, cwd)
  if not parent_pane_id then
    vim.notify("Neph/wezterm: cannot spawn – parent pane unavailable", vim.log.levels.ERROR)
    return nil
  end

  local bin = agent_config.cmd:match("^%S+")
  if not cmd_exists(bin) then
    vim.notify("Neph: command not found – " .. bin, vim.log.levels.ERROR)
    return nil
  end

  -- Build env prefix
  local env_parts = {}
  for k, v in pairs(config.env or {}) do
    env_parts[#env_parts + 1] = string.format("export %s=%s;", k, vim.fn.shellescape(v))
  end
  if vim.env.NVIM_SOCKET_PATH then
    env_parts[#env_parts + 1] = string.format("export NVIM_SOCKET_PATH=%s;", vim.fn.shellescape(vim.env.NVIM_SOCKET_PATH))
  end
  local env_str = table.concat(env_parts, " ")

  local full_cmd = env_str ~= "" and (env_str .. " " .. agent_config.cmd) or agent_config.cmd
  local spawn_cmd = string.format(
    "wezterm cli split-pane --pane-id %d --right --percent 50 --cwd %s -- sh -c %s 2>&1",
    parent_pane_id, vim.fn.shellescape(cwd), vim.fn.shellescape(full_cmd)
  )

  local result = vim.fn.system(spawn_cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify("Neph/wezterm: spawn failed – " .. vim.trim(result), vim.log.levels.ERROR)
    return nil
  end

  local pane_id = tonumber(vim.trim(result))
  if not pane_id then
    vim.notify("Neph/wezterm: could not parse pane ID", vim.log.levels.ERROR)
    return nil
  end

  if not wait_for_pane(pane_id, 5) then
    vim.notify("Neph/wezterm: pane did not appear within timeout", vim.log.levels.ERROR)
    pane_errors[pane_id] = (pane_errors[pane_id] or 0) + 1
    return nil
  end

  pane_errors[pane_id] = 0
  return { pane_id = pane_id, cmd = agent_config.cmd, cwd = cwd, name = termname, created_at = os.time() }
end

function M.focus(term_data)
  if not term_data.pane_id or not pane_exists(term_data.pane_id) then return false end
  activate_pane(term_data.pane_id)
  return true
end

function M.hide(term_data)
  if not term_data.pane_id then return end
  if pane_exists(term_data.pane_id) then kill_pane(term_data.pane_id) end
  term_data.pane_id = nil
  if parent_pane_id then activate_pane(parent_pane_id) end
end

function M.show(_term_data)
  return nil
end

function M.is_visible(term_data)
  return term_data ~= nil and term_data.pane_id ~= nil and pane_exists(term_data.pane_id)
end

function M.kill(term_data)
  if term_data.pane_id then kill_pane(term_data.pane_id) end
end

function M.cleanup_all(terminals)
  for _, td in pairs(terminals) do
    if td.pane_id then kill_pane(td.pane_id) end
  end
end

return M
