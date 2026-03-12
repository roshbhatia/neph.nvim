---@mod neph.config Configuration defaults and types
---
--- Review sign icons can be customized for ASCII-only terminals:
---   require("neph").setup({
---     review_signs = {
---       accept = "+",   -- default: ✓
---       reject = "-",   -- default: ✗
---       current = ">",  -- default: →
---     }
---   })

local M = {}

---@class neph.AgentDef
---@field name            string               Unique agent identifier
---@field label           string               Human-readable display name
---@field icon            string               Nerd Font icon
---@field cmd             string               CLI command to launch the agent
---@field args?           string[]             Static CLI arguments
---@field type?           string               "extension" | "hook" (nil = terminal-only)
---@field env?            table<string,string> Extra environment variables for this agent
---@field tools?          table                Declarative install manifest (symlinks, merges, builds, files)
---@field launch_args_fn? fun(root: string): string[]  Compute additional CLI args at launch time
---@field ready_pattern?  string               Lua pattern matched against terminal output to detect readiness
---@field full_cmd?       string               Resolved command (set by agents module at runtime)

---@class neph.Config
---@field keymaps?        boolean              Register default keymaps (default: true)
---@field env?            table<string,string> Extra environment variables forwarded to every agent
---@field file_refresh?   neph.FileRefreshConfig
---@field agents?         neph.AgentDef[]      Injected agent definitions (required)
---@field backend?        table                Injected backend module (required)
---@field review_signs?   neph.ReviewSignsConfig  Sign icons for diff review UI
---@field review_keymaps? neph.ReviewKeymapsConfig  Keymaps for diff review UI
---@field review?         neph.ReviewConfig     Review system configuration

---@class neph.FileRefreshConfig
---@field enable?         boolean  Periodically call :checktime (default: true)
---@field interval?       integer  Timer interval in ms (default: 1000)

---@class neph.ReviewSignsConfig
---@field accept?    string  Icon for accepted hunk (default: ✓)
---@field reject?    string  Icon for rejected hunk (default: ✗)
---@field current?   string  Icon for current hunk (default: →)

---@class neph.ReviewKeymapsConfig
---@field accept?      string  Accept current hunk (default: ga)
---@field reject?      string  Reject current hunk (default: gr)
---@field accept_all?  string  Accept all remaining (default: gA)
---@field reject_all?  string  Reject all remaining (default: gR)
---@field undo?        string  Clear decision (default: gu)
---@field submit?      string  Submit/finalize review (default: gs)
---@field quit?        string  Quit review (default: q)

---@class neph.ReviewConfig
---@field fs_watcher?     neph.FsWatcherConfig  Filesystem watcher for post-write review
---@field queue?          neph.ReviewQueueConfig  Sequential review queue
---@field pending_notify? boolean               Show notification when review is pending (default: true)

---@class neph.FsWatcherConfig
---@field enable?      boolean    Enable filesystem watcher (default: true)
---@field ignore?      string[]   Patterns to exclude from watching (default: node_modules, .git, dist, build, __pycache__)
---@field max_watched? integer    Maximum number of files to watch (default: 100)

---@class neph.ReviewQueueConfig
---@field enable? boolean    Enable sequential review queue (default: true)

---@type neph.Config
M.defaults = {
  keymaps = true,
  env = {},
  file_refresh = {
    enable = true,
    interval = 1000,
  },
  agents = nil,
  backend = nil,
  review_signs = {
    accept = "✓",
    reject = "✗",
    current = "→",
  },
  review_keymaps = {
    accept = "ga",
    reject = "gr",
    accept_all = "gA",
    reject_all = "gR",
    undo = "gu",
    submit = "gs",
    quit = "q",
  },
  review = {
    fs_watcher = {
      enable = true,
      ignore = { "node_modules", ".git", "dist", "build", "__pycache__" },
      max_watched = 100,
    },
    queue = {
      enable = true,
    },
    pending_notify = true,
  },
}

---@type neph.Config
M.current = {}

return M
