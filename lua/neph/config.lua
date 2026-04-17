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

---@class neph.IntegrationOverrides
---@field policy_engine?  string   Override policy engine id
---@field review_provider? string  Override review provider id
---@field formatter?      string   Override response formatter id
---@field adapter?        string   Override adapter id

---@alias neph.AgentType "extension" | "hook" | "terminal"

---@class neph.AgentDef
---@field name               string               Unique agent identifier
---@field label              string               Human-readable display name
---@field icon               string               Nerd Font icon
---@field cmd                string               CLI command to launch the agent
---@field args?              string[]             Static CLI arguments
---@field type?              neph.AgentType       "extension" | "hook" | "terminal" (nil = terminal-only)
---@field env?               table<string,string> Extra environment variables for this agent
---@field tools?             table                Declarative install manifest (symlinks, merges, builds, files)
---@field launch_args_fn?    fun(root: string): string[]  Compute additional CLI args at launch time
---@field ready_pattern?     string               Lua pattern matched against terminal output to detect readiness
---@field full_cmd?          string               Resolved command (set by agents module at runtime)
---@field integration_group? string               Integration group name for defaults
---@field integration_overrides? neph.IntegrationOverrides  Per-agent integration overrides
---@field integration_pipeline? table             Resolved integration pipeline (set at runtime by agents module)

---@class neph.IntegrationGroup
---@field policy_engine?  string   Policy engine id (e.g. "cupcake", "noop")
---@field review_provider? string  Review provider id (e.g. "vimdiff", "noop")
---@field formatter?      string   Response formatter id
---@field adapter?        string   Adapter id

---@class neph.ReviewProvider
---@field name string

--- Valid layout values for the diff review split.
---@alias neph.ReviewLayout "vertical" | "horizontal"

---@class neph.DiffPromptsConfig
---@field review? string  Prompt sent with broad diff reviews (head/staged/branch/file)
---@field hunk?   string  Prompt sent with single-hunk reviews

---@class neph.DiffConfig
---@field prompts?         neph.DiffPromptsConfig  Prompt text overrides
---@field branch_fallback? string                  Fallback ref when merge-base resolution fails (default: "HEAD~1")

---@class neph.Config
---@field keymaps?        boolean              Register default keymaps (default: true)
---@field env?            table<string,string> Extra environment variables forwarded to every agent
---@field file_refresh?   neph.FileRefreshConfig
---@field socket?         neph.SocketConfig
---@field agents?         neph.AgentDef[]      Injected agent definitions (required)
---@field backend?        table                Injected backend module (required)
---@field review_signs?   neph.ReviewSignsConfig  Sign icons for diff review UI
---@field review_keymaps? neph.ReviewKeymapsConfig  Keymaps for diff review UI
---@field review_layout?  neph.ReviewLayout    Default diff split layout: "vertical" (default) | "horizontal"
---@field review?         neph.ReviewConfig    Review system configuration
---@field review_provider? neph.ReviewProvider Explicit review provider (default: noop)
---@field integration_groups? table<string, neph.IntegrationGroup>  Integration group defaults
---@field integration_default_group? string    Default integration group name
---@field diff?           neph.DiffConfig      Git diff review configuration

---@class neph.SocketConfig
---@field enable?  boolean  Auto-create a Neovim RPC socket if none exists (default: true)
---@field path?    string   Custom socket path; defaults to a temp-dir path per-session

---@class neph.FileRefreshConfig
---@field enable?         boolean  Periodically call :checktime (default: true)
---@field interval?       integer  Timer interval in ms (default: 1000)

---@class neph.ReviewSignsConfig
---@field accept?    string  Icon for accepted hunk (default: ✓)
---@field reject?    string  Icon for rejected hunk (default: ✗)
---@field current?   string  Icon for current hunk (default: →)

---@class neph.ReviewKeymapsConfig
---@field accept?         string  Accept current hunk (default: ga)
---@field reject?         string  Reject current hunk (default: gr)
---@field accept_all?     string  Accept all remaining (default: gA)
---@field reject_all?     string  Reject all remaining (default: gR)
---@field undo?           string  Clear decision (default: gu)
---@field submit?         string  Submit/finalize review (default: gs)
---@field quit?           string  Quit review (default: q)
---@field rotate_layout?  string  Rotate split layout (default: gL)

---@class neph.ReviewConfig
---@field fs_watcher?     neph.FsWatcherConfig  Filesystem watcher for post-write review
---@field queue?          neph.ReviewQueueConfig  Sequential review queue
---@field pending_notify? boolean               Show notification when review is pending (default: true)

---@class neph.FsWatcherConfig
---@field enable?      boolean    Enable filesystem watcher (default: true)
--- Patterns to exclude from watching (default: node_modules, .git,
--- dist, build, __pycache__)
---@field ignore?      string[]
---@field max_watched? integer    Maximum number of files to watch (default: 100)

---@class neph.ReviewQueueConfig
---@field enable? boolean    Enable sequential review queue (default: true)

---@type neph.Config
M.defaults = {
  keymaps = true,
  env = {},
  socket = {
    enable = true,
    path = nil,
  },
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
    rotate_layout = "gL",
  },
  review_layout = "vertical",
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
  review_provider = nil,
  integration_groups = {
    default = { policy_engine = "noop", review_provider = "noop", formatter = "noop" },
    harness = { policy_engine = "cupcake", review_provider = "vimdiff", formatter = "noop" },
    hook = { policy_engine = "noop", review_provider = "vimdiff", formatter = "noop" },
    -- opencode_sse: review interception via opencode's HTTP permission API + SSE stream.
    -- No Cupcake required; neph subscribes to the SSE stream on session open.
    opencode_sse = { policy_engine = "noop", review_provider = "vimdiff", formatter = "noop" },
  },
  integration_default_group = "default",
  diff = {
    prompts = {
      review = "Review this diff carefully. Identify any bugs, logic errors, "
        .. "security issues, missing edge-cases, or places where the intent "
        .. "of the change is unclear. Be concise and specific — cite line "
        .. "numbers where relevant.",
      hunk = "Review this specific hunk. What does it change, is the change " .. "correct, and are there any issues?",
    },
    branch_fallback = "HEAD~1",
  },
}

---@type neph.Config
M.current = {}

return M
