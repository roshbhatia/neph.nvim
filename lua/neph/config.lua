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
---@field decide?      string  Accept/reject dialog for current hunk (default: <CR>)
---@field accept?      string  Shortcut: accept current hunk (default: <localleader>a)
---@field reject?      string  Shortcut: reject current hunk (default: <localleader>r)
---@field accept_all?  string  Shortcut: accept all remaining (default: <localleader>A)
---@field reject_all?  string  Shortcut: reject all remaining (default: <localleader>R)
---@field undo?        string  Shortcut: clear decision (default: <localleader>u)
---@field submit?      string  Submit/finalize review (default: <S-CR>)
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
    decide = "<CR>",
    accept = "<localleader>a",
    reject = "<localleader>r",
    accept_all = "<localleader>A",
    reject_all = "<localleader>R",
    undo = "<localleader>u",
    submit = "<S-CR>",
    quit = "q",
  },
}

---@type neph.Config
M.current = {}

return M
