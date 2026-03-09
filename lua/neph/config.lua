---@mod neph.config Configuration defaults and types
---
--- Review sign icons can be customized for ASCII-only terminals:
---   require("neph").setup({
---     review_signs = {
---       accept = "+",   -- default: ✓
---       reject = "-",   -- default: ✗
---       current = ">",  -- default: →
---       commented = "*" -- default: 󰟶
---     }
---   })

local M = {}

---@class neph.Config
---@field keymaps?        boolean              Register default keymaps (default: true)
---@field env?            table<string,string> Extra environment variables forwarded to every agent
---@field file_refresh?   neph.FileRefreshConfig
---@field agents?         neph.AgentDef[]      Injected agent definitions (required)
---@field backend?        table                Injected backend module (required)
---@field review_signs?   neph.ReviewSignsConfig  Sign icons for diff review UI
---@field review_keymaps? neph.ReviewKeymapsConfig  Keymaps for diff review UI

---@class neph.FileRefreshConfig
---@field enable?         boolean  Periodically call :checktime (default: true)

---@class neph.ReviewSignsConfig
---@field accept?    string  Icon for accepted hunk (default: ✓)
---@field reject?    string  Icon for rejected hunk (default: ✗)
---@field current?   string  Icon for current hunk (default: →)
---@field commented? string  Icon for rejected hunk with comment (default: 󰟶)

---@class neph.ReviewKeymapsConfig
---@field accept?      string  Accept current hunk (default: ga)
---@field reject?      string  Reject current hunk (default: gr)
---@field accept_all?  string  Accept all remaining (default: gA)
---@field reject_all?  string  Reject all remaining (default: gR)
---@field undo?        string  Clear decision back to undecided (default: gu)
---@field submit?      string  Submit/finalize review (default: <CR>)
---@field quit?        string  Quit review (default: q)

---@type neph.Config
M.defaults = {
  keymaps = true,
  env = {},
  file_refresh = {
    enable = true,
  },
  agents = nil,
  backend = nil,
  review_signs = {
    accept = "✓",
    reject = "✗",
    current = "→",
    commented = "󰟶",
  },
  review_keymaps = {
    accept = "ga",
    reject = "gr",
    accept_all = "gA",
    reject_all = "gR",
    undo = "gu",
    submit = "<CR>",
    quit = "q",
  },
}

---@type neph.Config
M.current = {}

return M
