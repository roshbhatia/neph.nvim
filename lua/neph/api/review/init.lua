---@mod neph.api.review Review orchestration
---@brief [[
--- Orchestrates diff review sessions. Opens a vimdiff tab with the
--- proposed content, runs the hunk-by-hunk review via engine + UI,
--- and writes the result envelope to a temp file for the neph CLI.
---@brief ]]

local M = {}

local engine = require("neph.api.review.engine")
local ui = require("neph.api.review.ui")

function M.open(params)
  local request_id = params.request_id
  local result_path = params.result_path
  local channel_id = params.channel_id
  local path = params.path
  local content = params.content

  local old_lines = {}
  local f = io.open(path, "r")
  if f then
    for line in f:lines() do
      table.insert(old_lines, line)
    end
    f:close()
  else
    -- File might not exist yet (new file)
    old_lines = {}
  end

  -- Handle trailing newline in content to match buffer line splitting behavior
  content = content or ""
  if content:sub(-1) == "\n" then
    content = content:sub(1, -2)
  end
  local new_lines = vim.split(content, "\n", { plain = true })

  local session = engine.create_session(old_lines, new_lines)

  if session.get_total_hunks() == 0 then
    local envelope = session.finalize()
    M.write_result(result_path, channel_id, request_id, envelope)
    return { ok = true, msg = "No changes" }
  end

  ui.setup_signs()
  local ui_state = ui.open_diff_tab(path, old_lines, new_lines)

  local result_written = false

  ui.start_review(session, ui_state, function(envelope)
    if result_written then
      return
    end
    result_written = true
    ui.cleanup(ui_state)
    M.write_result(result_path, channel_id, request_id, envelope)
  end)

  -- Handle manual tab close — check if our specific tabpage is gone,
  -- since TabClosed patterns use positional tab numbers which shift.
  vim.api.nvim_create_autocmd("TabClosed", {
    once = true,
    callback = function()
      if vim.api.nvim_tabpage_is_valid(ui_state.tab) then
        return true -- not our tab; re-register
      end
      if result_written then
        return
      end
      -- Tab closed before review finished — reject undecided, finalize
      result_written = true
      session.reject_all_remaining("User manually closed diff")
      local envelope = session.finalize()
      M.write_result(result_path, channel_id, request_id, envelope)
    end,
  })

  return { ok = true, msg = "Review started" }
end

function M.write_result(path, channel_id, request_id, envelope)
  envelope.request_id = request_id

  if path then
    local tmp_path = path .. ".tmp"
    local f, err = io.open(tmp_path, "w")
    if not f then
      vim.notify("Neph: failed to write review result: " .. (err or "unknown error"), vim.log.levels.ERROR)
      return
    end
    f:write(vim.json.encode(envelope))
    f:close()
    local ok, rename_err = os.rename(tmp_path, path)
    if not ok then
      vim.notify("Neph: failed to rename review result: " .. (rename_err or ""), vim.log.levels.ERROR)
    end
  end

  pcall(vim.rpcnotify, channel_id, "neph:review_done", envelope)
end

return M
