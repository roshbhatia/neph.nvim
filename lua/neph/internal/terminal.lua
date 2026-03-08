---@mod neph.terminal Terminal send helpers
---@brief [[
--- Thin wrapper around session.send() that also tracks the last prompt
--- per agent so it can be resent via <leader>jv.
---@brief ]]

local M = {}

---@type table<string,string>
local last_prompts = {}

--- Ensure *termname* is open/visible, then send *text* with submit.
--- Uses exponential backoff while waiting for the terminal to become ready.
---@param termname string
---@param text     string
function M.ensure_and_send(termname, text)
  last_prompts[termname] = text

  local session = require("neph.internal.session")

  if not session.is_visible(termname) then
    session.open(termname)
    session.focus(termname)

    local retries = 0
    local max_retries = 15
    local timer = vim.loop.new_timer()
    timer:start(
      25,
      50,
      vim.schedule_wrap(function()
        retries = retries + 1
        if session.is_visible(termname) then
          timer:stop()
          timer:close()
          session.send(termname, text, { submit = true })
        elseif retries >= max_retries then
          timer:stop()
          timer:close()
          vim.notify("Neph: terminal did not become ready in time", vim.log.levels.ERROR)
        end
      end)
    )
  else
    session.focus(termname)
    session.send(termname, text, { submit = true })
  end
end

---@param termname string
---@return string|nil
function M.get_last_prompt(termname)
  return last_prompts[termname]
end

---@param termname string
---@param prompt   string
function M.set_last_prompt(termname, prompt)
  last_prompts[termname] = prompt
end

return M
