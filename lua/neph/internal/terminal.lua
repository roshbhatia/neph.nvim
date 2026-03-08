---@mod neph.terminal Last-prompt tracker
---@brief [[
--- Tracks the last prompt sent per agent so it can be resent.
---@brief ]]

local M = {}

---@type table<string,string>
local last_prompts = {}

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
