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

  local session = require("neph.session")

  if not session.is_visible(termname) then
    session.open(termname)
    session.focus(termname)

    local retries = 15
    local delay_ms = 25

    for _ = 1, retries do
      if session.is_visible(termname) then
        session.send(termname, text, { submit = true })
        return
      end
      vim.fn.system(string.format("sleep %.3f", delay_ms / 1000))
      delay_ms = math.min(delay_ms * 1.5, 200)
    end

    vim.notify("Neph: terminal did not become ready in time", vim.log.levels.ERROR)
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
