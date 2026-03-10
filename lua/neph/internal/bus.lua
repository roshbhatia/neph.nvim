---@mod neph.bus Agent channel bus
---@brief [[
--- Manages persistent RPC channels for extension agents.
--- Extension agents register with their channel ID on connect.
--- Prompts are delivered via vim.rpcnotify (push, no polling).
---@brief ]]

local M = {}

local log = require("neph.internal.log")

---@type table<string, integer>  agent name → channel ID
local channels = {}

---@type userdata|nil  health-check timer
local health_timer = nil

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

---@param params table  { name: string, channel: integer }
---@return table  { ok: boolean, error?: string }
function M.register(params)
  local name = params and params.name
  local channel = params and params.channel

  if not name or type(name) ~= "string" then
    return { ok = false, error = "missing agent name" }
  end
  if not channel or type(channel) ~= "number" then
    return { ok = false, error = "missing channel ID" }
  end

  -- Validate that this is a known extension agent
  local agent = require("neph.internal.agents").get_by_name(name)
  if not agent or agent.type ~= "extension" then
    log.debug("bus", "register rejected: %s (not a known extension agent)", name)
    return { ok = false, error = "unknown agent or not type=extension: " .. name }
  end

  channels[name] = channel
  log.debug("bus", "registered: %s (channel=%d)", name, channel)

  -- Start health check if not already running
  M._ensure_health_timer()

  return { ok = true }
end

-- ---------------------------------------------------------------------------
-- Prompt delivery
-- ---------------------------------------------------------------------------

---@param name string  Agent name
---@param text string  Prompt text
---@param opts? table  { submit?: boolean }
---@return boolean  true if delivered, false if not connected
function M.send_prompt(name, text, opts)
  opts = opts or {}
  local ch = channels[name]
  if not ch then
    log.debug("bus", "send_prompt: %s not connected", name)
    return false
  end

  local full = opts.submit and (text .. "\n") or text
  local ok = pcall(vim.rpcnotify, ch, "neph:prompt", full)
  if ok then
    log.debug("bus", "send_prompt: %s (channel=%d, len=%d, submit=%s)", name, ch, #full, tostring(opts.submit or false))
  else
    log.debug("bus", "send_prompt: %s notify failed, removing channel", name)
    M.unregister(name)
  end
  return ok
end

-- ---------------------------------------------------------------------------
-- Query helpers
-- ---------------------------------------------------------------------------

---@param name string
---@return boolean
function M.is_connected(name)
  return channels[name] ~= nil
end

-- ---------------------------------------------------------------------------
-- Unregistration / cleanup
-- ---------------------------------------------------------------------------

---@param name string
function M.unregister(name)
  if channels[name] then
    log.debug("bus", "unregistered: %s", name)
    channels[name] = nil
  end
end

function M.cleanup_all()
  channels = {}
  if health_timer then
    pcall(health_timer.stop, health_timer)
    pcall(health_timer.close, health_timer)
    health_timer = nil
  end
end

-- ---------------------------------------------------------------------------
-- Health check timer
-- ---------------------------------------------------------------------------

function M._ensure_health_timer()
  if health_timer then
    return
  end
  health_timer = vim.uv.new_timer()
  health_timer:start(
    1000,
    1000,
    vim.schedule_wrap(function()
      for name, ch in pairs(channels) do
        local ok, err = pcall(vim.rpcnotify, ch, "neph:ping")
        if not ok then
          log.debug("bus", "health check: %s channel %d dead (%s), removing", name, ch, tostring(err))
          M.unregister(name)
        end
      end
      -- Stop timer if no channels remain
      if next(channels) == nil and health_timer then
        health_timer:stop()
        health_timer:close()
        health_timer = nil
      end
    end)
  )
end

-- ---------------------------------------------------------------------------
-- Testing helpers
-- ---------------------------------------------------------------------------

function M._get_channels()
  return channels
end

function M._reset()
  channels = {}
  if health_timer then
    pcall(health_timer.stop, health_timer)
    pcall(health_timer.close, health_timer)
    health_timer = nil
  end
end

return M
