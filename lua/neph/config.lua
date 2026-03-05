---@mod neph.config Configuration defaults and types
---
--- Review sign icons can be customized for ASCII-only terminals:
---   require("neph").setup({
---     review_signs = {
---       accept = "+",   -- default: ✓
---       reject = "-",   -- default: ✗
---       current = ">",  -- default: →
---       commented = "*" -- default: 💬
---     }
---   })

local M = {}

---@class neph.Config
---@field keymaps?        boolean              Register default keymaps (default: true)
---@field env?            table<string,string> Extra environment variables forwarded to every agent
---@field file_refresh?   neph.FileRefreshConfig
---@field agents?         neph.AgentDef[]      Override / extend the built-in agent list
---@field multiplexer?    "snacks"|"wezterm"|"tmux"|"zellij"  Terminal backend (default: "snacks")
---@field review_signs?   neph.ReviewSignsConfig  Sign icons for diff review UI

---@class neph.FileRefreshConfig
---@field enable?         boolean  Periodically call :checktime (default: true)

---@class neph.ReviewSignsConfig
---@field accept?    string  Icon for accepted hunk (default: ✓)
---@field reject?    string  Icon for rejected hunk (default: ✗)
---@field current?   string  Icon for current hunk (default: →)
---@field commented? string  Icon for rejected hunk with comment (default: 💬)

---@type neph.Config
M.defaults = {
  keymaps = true,
  env = {},
  file_refresh = {
    enable = true,
  },
  agents = nil,
  multiplexer = "snacks",
  review_signs = {
    accept = "✓",
    reject = "✗",
    current = "→",
    commented = "💬",
  },
}

---@type neph.Config
M.current = {}

return M
