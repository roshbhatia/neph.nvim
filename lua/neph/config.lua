---@mod neph.config Configuration defaults and types

local M = {}

---@class neph.Config
---@field keymaps?        boolean              Register default keymaps (default: true)
---@field env?            table<string,string> Extra environment variables forwarded to every agent
---@field file_refresh?   neph.FileRefreshConfig
---@field agents?         neph.AgentDef[]      Override / extend the built-in agent list
---@field multiplexer?    "native"|"wezterm"|"tmux"|"zellij"|nil  Force a specific terminal backend (default: nil = auto-detect)

---@class neph.FileRefreshConfig
---@field enable?         boolean  Periodically call :checktime (default: true)
---@field timer_interval? number   Milliseconds between checks (default: 1000)
---@field updatetime?     number   Override vim.o.updatetime (default: 750)

---@type neph.Config
M.defaults = {
  keymaps = true,
  env = {},
  file_refresh = {
    enable = true,
    timer_interval = 1000,
    updatetime = 750,
  },
  agents = nil,
  multiplexer = nil,
}

---@type neph.Config
M.current = {}

return M
