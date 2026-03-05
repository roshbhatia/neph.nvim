---@mod neph.config Configuration defaults and types

local M = {}

---@class neph.Config
---@field keymaps?        boolean              Register default keymaps (default: true)
---@field env?            table<string,string> Extra environment variables forwarded to every agent
---@field file_refresh?   neph.FileRefreshConfig
---@field agents?         neph.AgentDef[]      Override / extend the built-in agent list
---@field multiplexer?    "snacks"|"wezterm"|"tmux"|"zellij"  Terminal backend (default: "snacks")

---@class neph.FileRefreshConfig
---@field enable?         boolean  Periodically call :checktime (default: true)

---@type neph.Config
M.defaults = {
  keymaps = true,
  env = {},
  file_refresh = {
    enable = true,
  },
  agents = nil,
  multiplexer = "snacks",
}

---@type neph.Config
M.current = {}

return M
