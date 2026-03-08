---@type neph.AgentDef
return {
  name = "pi",
  label = "Pi",
  icon = "  ",
  cmd = "pi",
  args = { "--continue" },
  integration = {
    type = "extension",
    capabilities = { "review", "status", "checktime" },
  },
  ---@param _td table
  ---@param text string
  ---@param opts table
  ---@return boolean|nil
  send_adapter = function(_td, text, opts)
    if not vim.g.pi_active then
      return false
    end
    local full = opts and opts.submit and (text .. "\n") or text
    vim.g.neph_pending_prompt = full
    return true
  end,
}
