---@mod neph.keymaps Default keymap definitions
---@brief [[
--- Returns a list of keymap specs consumed by neph.setup().
--- All keymaps are under the <leader>j prefix.
---@brief ]]

local M = {}

local function get_active_agent()
  local session = require("neph.session")
  local active  = session.get_active()
  if not active then
    vim.notify("No active AI terminal – pick one with <leader>jj", vim.log.levels.WARN)
    return nil
  end
  return active
end

local function input_for_active(action, default_text)
  local active = get_active_agent()
  if not active then return end
  local agents = require("neph.agents")
  local agent  = agents.get_by_name(active)
  if not agent then return end
  require("neph.input").create_input(active, agent.icon, {
    action = action,
    default = default_text,
    on_confirm = function(text)
      require("neph.session").ensure_active_and_send(text)
    end,
  })
end

local function mode_input(action, normal_default, visual_default)
  return function()
    local mode = vim.fn.mode()
    input_for_active(action, mode:match("[vV]") and visual_default or normal_default)
  end
end

--- Generate the list of keymap specs.
---@return {[1]:string, [2]:function, mode?:string|string[], desc?:string}[]
function M.generate_all_keymaps()
  local picker = require("neph.picker")
  local history = require("neph.history")

  return {
    {
      "<leader>jj",
      picker.pick_agent,
      desc = "Neph: toggle / pick agent",
    },
    {
      "<leader>jJ",
      picker.kill_and_pick,
      desc = "Neph: kill session & pick new",
    },
    {
      "<leader>jx",
      picker.kill_active,
      desc = "Neph: kill active session",
    },
    {
      "<leader>ja",
      mode_input("Ask", " +cursor: ", " +selection: "),
      mode = { "n", "v" },
      desc = "Neph: ask active",
    },
    {
      "<leader>jf",
      function() input_for_active("Fix diagnostics", " Fix +diagnostics: ") end,
      desc = "Neph: fix diagnostics",
    },
    {
      "<leader>jc",
      mode_input("Comment", " Comment +cursor: ", " Comment +selection: "),
      mode = { "n", "v" },
      desc = "Neph: comment",
    },
    {
      "<leader>jv",
      function()
        local active = get_active_agent()
        if not active then return end
        local last = require("neph.terminal").get_last_prompt(active)
        if last and last ~= "" then
          require("neph.session").ensure_active_and_send(last)
        else
          vim.notify("No previous prompt found", vim.log.levels.WARN)
        end
      end,
      desc = "Neph: resend previous",
    },
    {
      "<leader>jh",
      function() history.pick(nil) end,
      desc = "Neph: browse history",
    },
  }
end

return M
