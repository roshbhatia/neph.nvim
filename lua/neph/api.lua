---@mod neph.api Public API for neph.nvim
---@brief [[
--- User-facing actions exposed as functions for keymap binding.
--- Use these with lazy.nvim's `keys` table or any keymap manager.
---
--- Example (lazy.nvim):
---
--- ```lua
--- {
---   "roshbhatia/neph.nvim",
---   keys = {
---     { "<leader>jj", function() require("neph.api").toggle() end, desc = "Neph: toggle / pick agent" },
---     { "<leader>ja", function() require("neph.api").ask() end, mode = { "n", "v" }, desc = "Neph: ask" },
---   },
--- }
--- ```
---@brief ]]

local M = {}

local gate_ui = require("neph.internal.gate_ui")

--- Get the active agent name, notifying if none is set.
---@return string|nil
local function get_active()
  local active = require("neph.internal.session").get_active()
  if not active then
    vim.notify("No active AI terminal – pick one with <leader>jj", vim.log.levels.WARN)
  end
  return active
end

--- Open the input prompt for the active agent.
---@param action string
---@param default_text string
local function input_for_active(action, default_text)
  local active = get_active()
  if not active then
    return
  end
  local agent = require("neph.internal.agents").get_by_name(active)
  if not agent then
    vim.notify("Agent '" .. active .. "' not found", vim.log.levels.WARN)
    return
  end
  require("neph.internal.input").create_input(active, agent.icon, {
    action = action,
    default = default_text,
    on_confirm = function(text)
      require("neph.internal.session").ensure_active_and_send(text)
    end,
  })
end

--- Toggle the active agent session, or open the picker if none is active.
function M.toggle()
  require("neph.internal.picker").pick_agent()
end

--- Kill the active session and open the picker to select a new one.
function M.kill_and_pick()
  require("neph.internal.picker").kill_and_pick()
end

--- Kill the active session.
function M.kill()
  require("neph.internal.picker").kill_active()
end

--- Open the ask prompt. In visual mode, prefills with +selection context.
function M.ask()
  local mode = vim.fn.mode()
  local default = mode:match("[vV\22]") and "+selection " or "+cursor "
  input_for_active("Ask", default)
end

--- Open the fix-diagnostics prompt.
function M.fix()
  input_for_active("Fix diagnostics", "Fix +diagnostics ")
end

--- Open the comment prompt. In visual mode, prefills with +selection context.
function M.comment()
  local mode = vim.fn.mode()
  local default = mode:match("[vV\22]") and "Comment +selection " or "Comment +cursor "
  input_for_active("Comment", default)
end

--- Open an interactive review of buffer vs disk changes.
---@param path? string  File path (defaults to current buffer's file)
---@return {ok: boolean, msg?: string, error?: string}
function M.review(path)
  if not path then
    local bufname = vim.api.nvim_buf_get_name(0)
    if bufname == "" then
      vim.notify("Neph: buffer has no file", vim.log.levels.ERROR)
      return { ok = false, error = "Buffer has no file" }
    end
    path = bufname
  end
  path = vim.fn.fnamemodify(path, ":p")
  local result = require("neph.api.review").open_manual(path)
  if not result.ok then
    vim.notify("Neph: " .. (result.error or "review failed"), vim.log.levels.ERROR)
  end
  return result
end

--- Resend the previous prompt to the active agent.
function M.resend()
  local active = get_active()
  if not active then
    return
  end
  local last = require("neph.internal.terminal").get_last_prompt(active)
  if last and last ~= "" then
    require("neph.internal.session").ensure_active_and_send(last)
  else
    vim.notify("No previous prompt found", vim.log.levels.WARN)
  end
end

--- Cycle the review gate: normal → hold → bypass → normal.
--- In hold mode, reviews accumulate silently until released.
--- In bypass mode, all agent writes are auto-accepted.
function M.gate()
  local gate = require("neph.internal.gate")
  local current = gate.get()
  if current == "normal" then
    gate.set("hold")
    gate_ui.set("hold")
    vim.notify("Neph: reviews held — writes will accumulate", vim.log.levels.INFO)
  elseif current == "hold" then
    gate.release()
    gate_ui.clear()
    require("neph.internal.review_queue").drain()
    vim.notify("Neph: gate released — draining pending reviews", vim.log.levels.INFO)
  else -- bypass
    gate.set("normal")
    gate_ui.clear()
    vim.notify("Neph: review gate restored to normal", vim.log.levels.INFO)
  end
end

--- Set gate to hold mode explicitly.
function M.gate_hold()
  require("neph.internal.gate").set("hold")
  gate_ui.set("hold")
  vim.notify("Neph: reviews held", vim.log.levels.INFO)
end

--- Set gate to bypass mode explicitly (auto-accepts all writes).
function M.gate_bypass()
  require("neph.internal.gate").set("bypass")
  gate_ui.set("bypass")
end

--- Release hold and drain accumulated reviews.
function M.gate_release()
  require("neph.internal.gate").release()
  gate_ui.clear()
  require("neph.internal.review_queue").drain()
  vim.notify("Neph: gate released", vim.log.levels.INFO)
end

--- Return the current gate state string.
---@return neph.GateState
function M.gate_status()
  return require("neph.internal.gate").get()
end

--- Open the NephStatus floating buffer showing agent integration state.
function M.tools_status()
  require("neph.api.status_buf").open()
end

--- Show a dry-run preview of what tools.install would change.
function M.tools_preview()
  require("neph.api.status_buf").open_preview()
end

--- Open the review queue inspector floating window.
function M.queue()
  require("neph.api.review.queue_ui").open()
end

return M
