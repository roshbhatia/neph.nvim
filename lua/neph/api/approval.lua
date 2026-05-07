---@mod neph.api.approval Approval / questionnaire prompts
---@brief [[
--- Lightweight `vim.ui.select`-based prompts for tool approvals, yes/no
--- decisions, and short questionnaires surfaced by peer agents.
---
--- Diff reviews (file edits) are intentionally NOT routed here — those use
--- the full-screen vimdiff tab in `neph.api.review` for granular per-hunk
--- control. This module is for "claude wants to run `rm -rf /tmp/...`,
--- allow?" or "opencode requests bash exec, approve?" — single-decision
--- prompts that don't need a diff editor.
---
--- Both nvim-side callers and peer-adapter callbacks share this surface:
---
---   require("neph.api.approval").ask({
---     prompt = "claude wants to run `rm -rf /tmp/foo`. Allow?",
---     options = { "Allow once", "Deny" },
---     callback = function(choice) ... end,
---   })
---
--- Honors gate state: bypass auto-allows the first option; hold queues
--- silently and drains on release.
---@brief ]]

local M = {}

local log = require("neph.internal.log")

--- A queue of pending approvals so concurrent requests don't show overlapping
--- prompts. FIFO; one prompt visible at a time.
---@type {prompt: string, options: string[], callback: fun(choice: string|nil), agent: string?}[]
local pending = {}
local active = nil

--- Drain the next pending approval if no prompt is currently active.
local function open_next()
  if active or #pending == 0 then
    return
  end
  active = table.remove(pending, 1)
  local req = active

  vim.schedule(function()
    vim.ui.select(req.options, {
      prompt = req.prompt,
      format_item = function(opt)
        return opt
      end,
    }, function(choice)
      active = nil
      if type(req.callback) == "function" then
        pcall(req.callback, choice)
      end
      open_next()
    end)
  end)
end

--- Ask the user a single multiple-choice question. Honors gate state:
---   - bypass: auto-selects the FIRST option (no UI)
---   - hold:   queues the request silently; drains via `M.drain()` on release
---   - normal: shows vim.ui.select immediately (or queues if another prompt is active)
---
---@param req {prompt: string, options: string[], callback: fun(choice: string|nil), agent: string?}
function M.ask(req)
  if type(req) ~= "table" or type(req.prompt) ~= "string" or type(req.options) ~= "table" then
    log.warn("approval", "ask: invalid request shape")
    return
  end
  if #req.options == 0 then
    log.warn("approval", "ask: empty options list")
    return
  end

  local gate = require("neph.internal.gate").get()
  if gate == "bypass" then
    -- Auto-select first option (the "allow" / "yes" by convention).
    log.debug("approval", "bypass: auto-selecting %q for %q", req.options[1], req.prompt)
    if type(req.callback) == "function" then
      vim.schedule(function()
        pcall(req.callback, req.options[1])
      end)
    end
    return
  end

  if gate == "hold" then
    table.insert(pending, req)
    log.debug("approval", "hold: queued %q (pending=%d)", req.prompt, #pending)
    return
  end

  -- normal: queue + drain
  table.insert(pending, req)
  open_next()
end

--- Drain queued approvals — call this when transitioning out of `hold` mode.
function M.drain()
  open_next()
end

--- Inspect pending count (test aid).
function M._pending_count()
  return #pending
end

--- Reset state (test aid).
function M._reset()
  pending = {}
  active = nil
end

return M
