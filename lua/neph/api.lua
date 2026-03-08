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

--- Browse prompt history for the active agent (or all agents).
function M.history()
  require("neph.internal.history").pick(nil)
end

return M
