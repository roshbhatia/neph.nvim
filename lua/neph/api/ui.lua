---@mod neph.api.ui Native UI bridge
---@brief [[
--- Bridge for generic UI requests from external agents.
--- Uses vim.ui.select, vim.ui.input, and vim.notify.
--- Responses are sent back via vim.rpcnotify.
---@brief ]]

local M = {}

---Map string levels to vim.log.levels
local levels = {
  info = vim.log.levels.INFO,
  warn = vim.log.levels.WARN,
  error = vim.log.levels.ERROR,
  debug = vim.log.levels.DEBUG,
  trace = vim.log.levels.TRACE,
}

---Display a notification.
---@param params {message: string, level: string?}
---@return {ok: boolean}
function M.notify(params)
  if not params or not params.message then
    return { ok = false, error = { code = "INVALID_PARAMS", message = "message is required" } }
  end
  local level = levels[params.level or "info"] or vim.log.levels.INFO
  vim.notify(params.message, level, { title = "Neph" })
  return { ok = true }
end

---Show a selection list.
---@param params {request_id: string, channel_id: number, title: string, options: string[]}
---@return {ok: boolean}
function M.select(params)
  if not params or not params.request_id or not params.channel_id or not params.options then
    return {
      ok = false,
      error = { code = "INVALID_PARAMS", message = "request_id, channel_id, and options are required" },
    }
  end

  vim.ui.select(params.options, {
    prompt = params.title or "Select:",
    kind = "neph_ui_select",
  }, function(choice)
    pcall(vim.rpcnotify, params.channel_id, "neph:ui_response", {
      request_id = params.request_id,
      choice = choice,
    })
  end)

  return { ok = true }
end

---Show a text input prompt.
---@param params {request_id: string, channel_id: number, title: string, default: string?}
---@return {ok: boolean}
function M.input(params)
  if not params or not params.request_id or not params.channel_id then
    return { ok = false, error = { code = "INVALID_PARAMS", message = "request_id and channel_id are required" } }
  end

  vim.ui.input({
    prompt = params.title or "Input:",
    default = params.default or "",
  }, function(choice)
    pcall(vim.rpcnotify, params.channel_id, "neph:ui_response", {
      request_id = params.request_id,
      choice = choice,
    })
  end)

  return { ok = true }
end

return M
