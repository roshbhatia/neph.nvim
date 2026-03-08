---@type neph.AgentDef
return {
  name = "pi",
  label = "Pi",
  icon = "",
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
    local full = opts and opts.submit and (text .. "\n") or text
    vim.g.neph_pending_prompt = full
    require("neph.internal.log").debug(
      "pi",
      "send_adapter: set neph_pending_prompt (submit=%s, len=%d)",
      tostring(opts and opts.submit or false),
      #full
    )
    return true
  end,
  tools = {
    symlinks = {
      { src = "pi/package.json", dst = "~/.pi/agent/extensions/nvim/package.json" },
      { src = "pi/dist", dst = "~/.pi/agent/extensions/nvim/dist" },
    },
    builds = {
      { dir = "pi", src_dirs = { ".", "../lib" }, check = "dist/pi.js" },
    },
    files = {
      {
        dst = "~/.pi/agent/extensions/nvim/index.ts",
        content = 'export { default } from "./dist/pi.js";',
        mode = "create_only",
      },
    },
  },
}
