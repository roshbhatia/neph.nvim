---@mod neph.backends.zellij Zellij pane backend
---@brief [[
--- Spawns AI agent terminals as Zellij panes to the right of the current Neovim pane.
--- Requires ZELLIJ env var and `zellij` CLI. Uses FIFO to capture pane ID from
--- spawned process; uses relative focus (move-focus right/left) for send/focus/kill.
--- Single agent pane at a time. ready_pattern not supported; uses configurable delay.
---@brief ]]

local M = {}

M.single_pane_only = true

local config = {}
local READY_DELAY_MS = 2000
local FIFO_TIMEOUT_MS = 30000

local function cmd_exists(cmd)
  return vim.fn.executable(cmd) == 1
end

local function zellij_action(...)
  local args = { "zellij", "action", ... }
  local result = vim.fn.system(args)
  return vim.v.shell_error == 0, result
end

--- Run zellij action via jobstart (async, non-blocking).
---@param actions string[]  e.g. {"move-focus", "right"}
---@param on_exit? fun(code: number)
local function zellij_action_async(actions, on_exit)
  local args = vim.list_extend({ "zellij", "action" }, actions)
  local job_id = vim.fn.jobstart(args, {
    on_exit = on_exit and vim.schedule_wrap(on_exit) or nil,
  })
  return job_id > 0
end

--- Run multiple zellij actions in sequence via a single shell command.
---@param action_sequences string[][]  e.g. {{"move-focus","left"}, {"write-chars","hi"}, {"move-focus","right"}}
---@param on_exit? fun(code: number)
local function zellij_actions_chain(action_sequences, on_exit)
  local parts = {}
  for _, actions in ipairs(action_sequences) do
    local cmd = "zellij action " .. table.concat(vim.tbl_map(vim.fn.shellescape, actions), " ")
    parts[#parts + 1] = cmd
  end
  local full_cmd = table.concat(parts, " && ")
  local job_id = vim.fn.jobstart({ "sh", "-c", full_cmd }, {
    on_exit = on_exit and vim.schedule_wrap(on_exit) or nil,
  })
  return job_id > 0
end

--- Parse list-clients output for pane IDs. Returns set of pane IDs found.
---@param output string
---@return table<string, boolean>
local function parse_list_clients(output)
  local seen = {}
  if not output or output == "" then
    return seen
  end
  for line in output:gmatch("[^\n]+") do
    -- Format: "CLIENT_ID ZELLIJ_PANE_ID RUNNING_COMMAND" or "1  terminal_3  vim ..."
    local parts = {}
    for part in line:gmatch("%S+") do
      parts[#parts + 1] = part
    end
    if #parts >= 2 then
      local pane_id = parts[2]
      if pane_id:match("^terminal_") or pane_id:match("^%d+$") then
        seen[pane_id] = true
        if pane_id:match("^%d+$") then
          seen["terminal_" .. pane_id] = true
        end
      end
    end
  end
  return seen
end

--- Normalize pane ID for matching (bare number -> terminal_N).
---@param pane_id string
---@return string
local function normalize_pane_id(pane_id)
  if not pane_id or pane_id == "" then
    return ""
  end
  if pane_id:match("^%d+$") then
    return "terminal_" .. pane_id
  end
  return pane_id
end

-- ---------------------------------------------------------------------------

function M.setup(opts)
  config = opts or {}
  config.zellij_ready_delay_ms = config.zellij_ready_delay_ms or READY_DELAY_MS
  if not vim.env.ZELLIJ and not vim.env.ZELLIJ_SESSION_NAME then
    vim.notify("Neph/zellij: ZELLIJ not set – not in a Zellij session", vim.log.levels.WARN)
  end
end

function M.open(termname, agent_config, cwd)
  if not vim.env.ZELLIJ and not vim.env.ZELLIJ_SESSION_NAME then
    vim.notify("Neph/zellij: cannot spawn – not in a Zellij session", vim.log.levels.ERROR)
    return nil
  end

  if not cmd_exists("zellij") then
    vim.notify("Neph/zellij: zellij command not found", vim.log.levels.ERROR)
    return nil
  end

  local bin = agent_config.cmd:match("^%S+")
  if not cmd_exists(bin) then
    vim.notify("Neph: command not found – " .. bin, vim.log.levels.ERROR)
    return nil
  end

  -- FIFO path for pane ID capture
  local fifo_path = "/tmp/neph-zellij-" .. vim.fn.getpid() .. "-" .. tostring(vim.uv.hrtime())
  vim.fn.system("mkfifo " .. vim.fn.shellescape(fifo_path) .. " 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    vim.notify("Neph/zellij: failed to create FIFO", vim.log.levels.ERROR)
    return nil
  end

  -- Build env and command (same pattern as wezterm)
  local env_parts = {}
  local merged_env = vim.tbl_extend("force", config.env or {}, agent_config.env or {})
  for k, v in pairs(merged_env) do
    env_parts[#env_parts + 1] = string.format("export %s=%s;", k, vim.fn.shellescape(v))
  end
  if vim.v.servername then
    env_parts[#env_parts + 1] = string.format("export NVIM_SOCKET_PATH=%s;", vim.fn.shellescape(vim.v.servername))
  end
  local env_str = table.concat(env_parts, " ")
  local agent_cmd = agent_config.full_cmd or agent_config.cmd
  local full_cmd = env_str ~= "" and (env_str .. " " .. agent_cmd) or agent_cmd

  -- Inner shell: write pane ID to FIFO, then exec agent
  local inner_cmd =
    string.format('echo "$ZELLIJ_PANE_ID" > %s; exec %s', vim.fn.shellescape(fifo_path), vim.fn.shellescape(full_cmd))

  local td = {
    pane_id = nil,
    cmd = agent_config.cmd,
    cwd = cwd,
    name = termname,
    ready = false,
    fifo_path = fifo_path,
  }

  -- Timeout: if we don't get pane ID, fail
  local timeout_timer = vim.uv.new_timer()
  timeout_timer:start(
    FIFO_TIMEOUT_MS,
    0,
    vim.schedule_wrap(function()
      if td.pane_id then
        return
      end
      timeout_timer:close()
      pcall(vim.fn.delete, fifo_path)
      vim.notify("Neph/zellij: timeout waiting for pane ID", vim.log.levels.WARN)
      td.ready = true
      if td.on_ready then
        td.on_ready()
      end
    end)
  )

  -- Start cat to read from FIFO (blocks until writer opens)
  vim.fn.jobstart({ "cat", fifo_path }, {
    on_stdout = vim.schedule_wrap(function(_, data)
      if td.pane_id then
        return
      end
      if data and #data > 0 then
        local raw = vim.trim(table.concat(data, ""))
        if raw ~= "" then
          td.pane_id = normalize_pane_id(raw)
          timeout_timer:stop()
          timeout_timer:close()
          pcall(vim.fn.delete, fifo_path)
          td.fifo_path = nil
          -- Ready after delay (no pattern support)
          local delay = config.zellij_ready_delay_ms or READY_DELAY_MS
          vim.defer_fn(function()
            td.ready = true
            if td.on_ready then
              td.on_ready()
            end
          end, delay)
        end
      end
    end),
    on_exit = vim.schedule_wrap(function(_, code)
      if code ~= 0 and not td.pane_id then
        vim.notify("Neph/zellij: FIFO read failed (exit " .. code .. ")", vim.log.levels.WARN)
      end
    end),
  })

  -- Spawn zellij run
  local zellij_cmd =
    string.format("zellij run -d right --cwd %s -- sh -c %s", vim.fn.shellescape(cwd), vim.fn.shellescape(inner_cmd))
  vim.fn.jobstart({ "sh", "-c", zellij_cmd }, {
    on_exit = vim.schedule_wrap(function(_, code)
      if code ~= 0 then
        vim.notify("Neph/zellij: spawn failed (exit " .. code .. ")", vim.log.levels.ERROR)
      end
    end),
  })

  return td
end

function M.focus(term_data)
  if not term_data or not M.is_visible(term_data) then
    return false
  end
  zellij_action_async({ "move-focus", "right" })
  return true
end

function M.hide(term_data)
  if not term_data then
    return
  end
  -- Ensure we're on agent: move-focus left (from agent->Neovim), then right (->agent), then close
  zellij_actions_chain({
    { "move-focus", "left" },
    { "move-focus", "right" },
    { "close-pane" },
  })
  term_data.pane_id = nil
end

function M.show(_term_data)
  return nil
end

function M.is_visible(term_data)
  if not term_data or not term_data.pane_id then
    return false
  end
  local ok, output = zellij_action("list-clients")
  if not ok then
    return false
  end
  local seen = parse_list_clients(output)
  local normalized = normalize_pane_id(term_data.pane_id)
  return seen[term_data.pane_id] == true or seen[normalized] == true
end

function M.kill(term_data)
  if not term_data then
    return
  end
  zellij_actions_chain({
    { "move-focus", "left" },
    { "move-focus", "right" },
    { "close-pane" },
  })
  term_data.pane_id = nil
end

function M.cleanup_all(terminals)
  for _, td in pairs(terminals) do
    if td and td.pane_id then
      M.kill(td)
    end
  end
end

---@param td table  term_data
---@param text string
---@param opts? {submit?: boolean}
function M.send(td, text, opts)
  opts = opts or {}
  if not td or not M.is_visible(td) then
    return
  end
  local full_text = opts.submit and (text .. "\n") or text
  -- move-focus right -> write-chars -> move-focus left
  local escaped = vim.fn.shellescape(full_text)
  zellij_actions_chain({
    { "move-focus", "right" },
    { "write-chars", escaped },
    { "move-focus", "left" },
  }, function(_, code)
    if code ~= 0 then
      vim.notify("Neph/zellij: send-text failed (exit " .. code .. ")", vim.log.levels.WARN)
    end
  end)
end

return M
