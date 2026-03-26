---@mod neph.api.status_buf Integration status floating window
---@brief [[
--- Opens a floating buffer showing agent integration state, gate mode,
--- and tool installation status.
---@brief ]]

local M = {}

--- Open the integration status floating window.
function M.open()
  local lines = {}
  local gate_state = require("neph.internal.gate").get()
  table.insert(lines, "Neph Integration Status")
  table.insert(lines, string.format("Gate: %s", gate_state:upper()))
  table.insert(lines, "")
  table.insert(lines, string.format("  %-16s %-10s %-14s %s", "agent", "group", "tools", "review"))
  table.insert(lines, "  " .. string.rep("─", 52))

  local agents = require("neph.internal.agents").get_all()
  for _, agent in ipairs(agents) do
    local pipeline = agent.integration_pipeline or {}
    local review = pipeline.review_provider or "noop"
    local group = agent.integration_group or "default"
    local tools_str = agent.tools and "● tools" or "— none"
    table.insert(lines, string.format("  %-16s %-10s %-14s %s", agent.name, group, tools_str, review))
  end

  table.insert(lines, "")
  table.insert(lines, "  [i] install all  [p] preview  [q] close")

  -- create floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"

  local width = 60
  local height = #lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " Neph ",
    title_pos = "center",
  })

  -- keymaps
  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, opts)
  vim.keymap.set("n", "i", function()
    vim.api.nvim_win_close(win, true)
    vim.cmd("NephInstall")
  end, opts)
  vim.keymap.set("n", "p", function()
    vim.api.nvim_win_close(win, true)
    vim.cmd("NephInstall --preview")
  end, opts)
end

--- Open the status window with a preview note.
--- For a detailed preview, use :NephInstall --preview.
function M.open_preview()
  vim.notify("Neph: preview — run :NephInstall --preview for details", vim.log.levels.INFO)
  M.open()
end

return M
