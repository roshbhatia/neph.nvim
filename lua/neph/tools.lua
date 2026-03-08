---@mod neph.tools Tool installation helpers
---@brief [[
--- Auto-symlinks bundled companion tools to their expected locations.
---
--- Called once from neph.setup(). Safe to call multiple times (uses ln -sf).
---
--- Symlinks created:
---   tools/neph-cli/dist/index.js → ~/.local/bin/neph
---   tools/pi/package.json        → ~/.pi/agent/extensions/nvim/package.json
---   tools/pi/dist                → ~/.pi/agent/extensions/nvim/dist
---
--- Files created:
---   ~/.pi/agent/extensions/nvim/index.ts (wrapper)
---@brief ]]

local M = {}

-- Resolve the plugin root (two levels up from this file: lua/neph/tools.lua → ../../)
local function plugin_root()
  local src = debug.getinfo(1, "S").source
  -- source is "@/path/to/lua/neph/tools.lua" — strip the leading "@"
  local file = src:match("^@(.+)$") or src
  -- Go up two directories: neph/ → lua/ → plugin root
  return vim.fn.fnamemodify(file, ":h:h:h")
end

---@class neph.ToolSpec
---@field src  string  Path relative to tools/ inside the plugin root
---@field dst  string  Absolute destination path (may use ~)

---@class neph.MergeSpec
---@field src     string  Path relative to tools/ inside the plugin root
---@field dst     string  Absolute destination path (may use ~)
---@field key     string  JSON key to merge

---@class neph.ToolSpec
---@field src    string       Path relative to tools/ inside the plugin root
---@field dst    string       Absolute destination path (may use ~)
---@field agent? string       Agent name this belongs to (nil = always installed, e.g. neph CLI)

---@type neph.ToolSpec[]
local TOOLS = {
  { src = "neph-cli/dist/index.js", dst = "~/.local/bin/neph" },
  { src = "pi/package.json", dst = "~/.pi/agent/extensions/nvim/package.json", agent = "pi" },
  { src = "pi/dist", dst = "~/.pi/agent/extensions/nvim/dist", agent = "pi" },
  -- Cursor hooks (symlink — standalone file)
  { src = "cursor/hooks.json", dst = "~/.cursor/hooks.json", agent = "cursor" },
  -- Amp plugin (symlink — single TS file, Bun-based)
  { src = "amp/neph-plugin.ts", dst = "~/.config/amp/plugins/neph-plugin.ts", agent = "amp" },
  -- OpenCode custom tools (symlink — standalone files)
  { src = "opencode/write.ts", dst = "~/.config/opencode/tools/write.ts", agent = "opencode" },
  { src = "opencode/edit.ts", dst = "~/.config/opencode/tools/edit.ts", agent = "opencode" },
}

---@class neph.MergeSpec
---@field src     string  Path relative to tools/ inside the plugin root
---@field dst     string  Absolute destination path (may use ~)
---@field key     string  JSON key to merge
---@field agent?  string  Agent name this belongs to (nil = always installed)

--- Settings files that need JSON merge (not symlink)
---@type neph.MergeSpec[]
local MERGE_TOOLS = {
  { src = "claude/settings.json", dst = "~/.claude/settings.json", key = "hooks", agent = "claude" },
  { src = "gemini/settings.json", dst = "~/.gemini/settings.json", key = "hooks", agent = "gemini" },
}

--- Check if a hook entry already exists in a list (match on matcher + first command).
---@param list table[]  Existing hook entries
---@param entry table   Entry to check
---@return boolean
local function hook_entry_exists(list, entry)
  for _, existing in ipairs(list) do
    if existing.matcher == entry.matcher then
      -- Same matcher — check if commands match
      if existing.hooks and entry.hooks and #existing.hooks > 0 and #entry.hooks > 0 then
        if existing.hooks[1].command == entry.hooks[1].command then
          return true
        end
      end
    end
  end
  return false
end

--- Additively merge hooks from source JSON into destination JSON file.
--- Existing hooks in destination are preserved. Neph hooks are appended
--- only if not already present (idempotent). Non-hook keys are untouched.
---@param src_path string  Absolute path to source JSON
---@param dst_path string  Absolute path to destination JSON
---@param key      string  JSON key to merge (e.g. "hooks")
local function json_merge(src_path, dst_path, key)
  local src_content = vim.fn.readfile(src_path)
  if not src_content or #src_content == 0 then
    return
  end
  local src_json = vim.json.decode(table.concat(src_content, "\n"))
  if not src_json or not src_json[key] then
    return
  end

  local dst_json = {}
  if vim.fn.filereadable(dst_path) == 1 then
    local dst_content = vim.fn.readfile(dst_path)
    if dst_content and #dst_content > 0 then
      local ok, parsed = pcall(vim.json.decode, table.concat(dst_content, "\n"))
      if ok and parsed then
        dst_json = parsed
      end
    end
  end

  -- Additive merge: for each event type in source hooks, append entries
  -- that don't already exist in the destination
  if not dst_json[key] then
    dst_json[key] = {}
  end
  for event_type, entries in pairs(src_json[key]) do
    if not dst_json[key][event_type] then
      dst_json[key][event_type] = {}
    end
    for _, entry in ipairs(entries) do
      if not hook_entry_exists(dst_json[key][event_type], entry) then
        table.insert(dst_json[key][event_type], entry)
      end
    end
  end

  vim.fn.mkdir(vim.fn.fnamemodify(dst_path, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(dst_json) }, dst_path)
end

--- Find the newest mtime among all .ts files in a directory (non-recursive for flat, recursive for src/).
---@param dir string  Directory to scan
---@return number  newest mtime (0 if no files found)
local function newest_ts_mtime(dir)
  local glob = vim.fn.glob(dir .. "/**/*.ts", false, true)
  local newest = 0
  for _, f in ipairs(glob) do
    local mt = vim.fn.getftime(f)
    if mt > newest then
      newest = mt
    end
  end
  return newest
end

--- Build TypeScript tools that require bundling.
--- Rebuilds if dist is missing OR if any source .ts file is newer than dist.
---@param root string  Plugin root path
local function build_if_needed(root)
  local builds = {
    { dir = "neph-cli", src_dirs = { "src" }, check = "dist/index.js" },
    { dir = "pi", src_dirs = { ".", "../lib" }, check = "dist/pi.js" },
  }
  for _, b in ipairs(builds) do
    local tool_dir = root .. "/tools/" .. b.dir
    local check_file = tool_dir .. "/" .. b.check
    local pkg = tool_dir .. "/package.json"
    if vim.fn.filereadable(pkg) == 1 then
      local needs_build = vim.fn.filereadable(check_file) == 0
      if not needs_build then
        local dst_mtime = vim.fn.getftime(check_file)
        for _, sd in ipairs(b.src_dirs) do
          local src_mtime = newest_ts_mtime(tool_dir .. "/" .. sd)
          if src_mtime > dst_mtime then
            needs_build = true
            break
          end
        end
      end

      if needs_build then
        local cmd = "cd "
          .. vim.fn.shellescape(tool_dir)
          .. " && npm install --ignore-scripts 2>/dev/null && npm run build 2>&1"
        local result = vim.fn.system({ "sh", "-c", cmd })
        if vim.v.shell_error ~= 0 then
          vim.notify("Neph: build failed for " .. b.dir .. ": " .. result, vim.log.levels.WARN)
        end
      end
    end
  end
end

--- Check if an agent is in the enabled list (nil = all enabled).
---@param agent string|nil  Agent name (nil = always enabled, e.g. neph CLI)
---@param enabled string[]|nil  Allowlist (nil = all enabled)
---@return boolean
local function is_agent_enabled(agent, enabled)
  if not agent then
    return true -- no agent tag = always installed (e.g. neph CLI)
  end
  if not enabled then
    return true -- no allowlist = all agents enabled
  end
  for _, name in ipairs(enabled) do
    if name == agent then
      return true
    end
  end
  return false
end

--- Install (symlink) all bundled tools to their canonical locations.
--- When `config.enabled_agents` is set, only installs tools for listed agents.
--- The neph CLI is always installed regardless of the allowlist.
function M.install()
  local root = plugin_root()
  local enabled = require("neph.config").current.enabled_agents

  build_if_needed(root)

  for _, tool in ipairs(TOOLS) do
    if not is_agent_enabled(tool.agent, enabled) then
      goto continue_tool
    end
    local src = root .. "/tools/" .. tool.src
    local dst = vim.fn.expand(tool.dst)

    -- Check if src exists (file or directory)
    local exists = vim.fn.filereadable(src) == 1 or vim.fn.isdirectory(src) == 1
    if not exists then
      vim.notify(string.format("Neph: tool not found, skipping symlink: %s", src), vim.log.levels.WARN)
    else
      vim.fn.mkdir(vim.fn.fnamemodify(dst, ":h"), "p")
      vim.fn.system({ "ln", "-sfn", src, dst })
    end
    ::continue_tool::
  end

  -- JSON merge installs (claude, gemini settings)
  for _, spec in ipairs(MERGE_TOOLS) do
    if not is_agent_enabled(spec.agent, enabled) then
      goto continue_merge
    end
    local src = root .. "/tools/" .. spec.src
    local dst = vim.fn.expand(spec.dst)
    if vim.fn.filereadable(src) == 1 then
      json_merge(src, dst, spec.key)
    else
      vim.notify(string.format("Neph: tool not found, skipping merge: %s", src), vim.log.levels.WARN)
    end
    ::continue_merge::
  end

  -- Create pi extension index.ts wrapper (only if pi is enabled)
  if is_agent_enabled("pi", enabled) then
    local pi_ext_dir = vim.fn.expand("~/.pi/agent/extensions/nvim")
    local pi_index = pi_ext_dir .. "/index.ts"
    if vim.fn.isdirectory(pi_ext_dir) == 1 and vim.fn.filereadable(pi_index) == 0 then
      vim.fn.writefile({ 'export { default } from "./dist/pi.js";' }, pi_index)
    end
  end
end

return M
