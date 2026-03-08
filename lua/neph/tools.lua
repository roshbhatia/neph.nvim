---@mod neph.tools Tool installation helpers
---@brief [[
--- Auto-symlinks bundled companion tools to their expected locations.
---
--- Uses a stamp file to skip reinstallation when nothing has changed.
--- The stamp records the plugin root mtime; install only runs when
--- the plugin directory is newer than the stamp.
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
  local file = src:match("^@(.+)$") or src
  return vim.fn.fnamemodify(file, ":h:h:h")
end

---@class neph.ToolSpec
---@field src    string       Path relative to tools/ inside the plugin root
---@field dst    string       Absolute destination path (may use ~)
---@field agent? string       Agent name this belongs to (nil = always installed, e.g. neph CLI)

---@type neph.ToolSpec[]
local TOOLS = {
  { src = "neph-cli/dist/index.js", dst = "~/.local/bin/neph" },
  { src = "pi/package.json", dst = "~/.pi/agent/extensions/nvim/package.json", agent = "pi" },
  { src = "pi/dist", dst = "~/.pi/agent/extensions/nvim/dist", agent = "pi" },
  { src = "cursor/hooks.json", dst = "~/.cursor/hooks.json", agent = "cursor" },
  { src = "amp/neph-plugin.ts", dst = "~/.config/amp/plugins/neph-plugin.ts", agent = "amp" },
  { src = "opencode/write.ts", dst = "~/.config/opencode/tools/write.ts", agent = "opencode" },
  { src = "opencode/edit.ts", dst = "~/.config/opencode/tools/edit.ts", agent = "opencode" },
}

---@class neph.MergeSpec
---@field src     string  Path relative to tools/ inside the plugin root
---@field dst     string  Absolute destination path (may use ~)
---@field key     string  JSON key to merge
---@field agent?  string  Agent name this belongs to (nil = always installed)

---@type neph.MergeSpec[]
local MERGE_TOOLS = {
  { src = "claude/settings.json", dst = "~/.claude/settings.json", key = "hooks", agent = "claude" },
  { src = "gemini/settings.json", dst = "~/.gemini/settings.json", key = "hooks", agent = "gemini" },
}

-- ---------------------------------------------------------------------------
-- Stamp file: skip install when nothing changed
-- ---------------------------------------------------------------------------

local STAMP_NAME = "neph_install.stamp"

--- Get the stamp file path (in Neovim's data directory).
---@return string
local function stamp_path()
  return vim.fn.stdpath("data") .. "/" .. STAMP_NAME
end

--- Check if install can be skipped. Compares the plugin root's mtime
--- against the stamp file's mtime. If the stamp is newer, nothing changed.
---@param root string
---@return boolean  true if install should be skipped
local function is_up_to_date(root)
  local sp = stamp_path()
  local stamp_mt = vim.fn.getftime(sp)
  if stamp_mt < 0 then
    return false -- no stamp = first install
  end
  -- Check if any tools/ source is newer than stamp
  local tools_dir = root .. "/tools"
  local tools_mt = vim.fn.getftime(tools_dir)
  return tools_mt <= stamp_mt
end

--- Touch the stamp file.
local function touch_stamp()
  local sp = stamp_path()
  vim.fn.writefile({ tostring(os.time()) }, sp)
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Check if an agent is registered (injected via setup).
---@param agent string|nil
---@param registered table<string, boolean>
---@return boolean
local function is_agent_registered(agent, registered)
  if not agent then
    return true -- tools without an agent are always installed
  end
  return registered[agent] == true
end

--- Check if a hook entry already exists in a list.
---@param list table[]
---@param entry table
---@return boolean
local function hook_entry_exists(list, entry)
  for _, existing in ipairs(list) do
    if existing.matcher == entry.matcher then
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
---@param src_path string
---@param dst_path string
---@param key string
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

-- ---------------------------------------------------------------------------
-- Install logic
-- ---------------------------------------------------------------------------

--- Build a shell script that does everything: mtime checks, builds, symlinks.
--- The entire script runs in a background job — zero main-thread blocking.
---@param root string
---@return string
--- Build a set of registered agent names from the injected agents.
---@return table<string, boolean>
local function get_registered_agents()
  local agents = require("neph.internal.agents").get_all()
  local set = {}
  for _, a in ipairs(agents) do
    set[a.name] = true
  end
  return set
end

local function build_install_script(root)
  local registered = get_registered_agents()
  local lines = { "#!/bin/sh" }

  -- Symlinks
  for _, tool in ipairs(TOOLS) do
    if is_agent_registered(tool.agent, registered) then
      local src = root .. "/tools/" .. tool.src
      local dst = vim.fn.expand(tool.dst)
      local dst_dir = vim.fn.fnamemodify(dst, ":h")
      table.insert(lines, string.format("mkdir -p '%s'", dst_dir))
      table.insert(lines, string.format("[ -e '%s' ] && ln -sfn '%s' '%s'", src, src, dst))
    end
  end

  -- Conditional builds: only if dist is missing or source is newer
  local builds = {
    { dir = "neph-cli", src_dirs = { "src" }, check = "dist/index.js" },
    { dir = "pi", src_dirs = { ".", "../lib" }, check = "dist/pi.js" },
  }
  for _, b in ipairs(builds) do
    local tool_dir = root .. "/tools/" .. b.dir
    -- Let the shell do the mtime comparison — no Lua glob needed
    table.insert(lines, string.format(
      "if [ -f '%s/package.json' ]; then",
      tool_dir
    ))
    table.insert(lines, string.format(
      "  NEEDS_BUILD=0; CHECK='%s/%s'",
      tool_dir, b.check
    ))
    table.insert(lines, "  if [ ! -f \"$CHECK\" ]; then NEEDS_BUILD=1; else")
    for _, sd in ipairs(b.src_dirs) do
      table.insert(lines, string.format(
        "    if [ -n \"$(find '%s/%s' -name '*.ts' -newer \"$CHECK\" 2>/dev/null | head -1)\" ]; then NEEDS_BUILD=1; fi",
        tool_dir, sd
      ))
    end
    table.insert(lines, "  fi")
    table.insert(lines, string.format(
      "  if [ \"$NEEDS_BUILD\" = 1 ]; then cd '%s' && npm install --ignore-scripts 2>/dev/null && npm run build 2>&1; fi",
      tool_dir
    ))
    table.insert(lines, "fi")
  end

  return table.concat(lines, "\n")
end

--- JSON merges and pi wrapper (must run on main thread for vim.fn access).
---@param root string
local function do_json_merges(root)
  local registered = get_registered_agents()

  for _, spec in ipairs(MERGE_TOOLS) do
    if is_agent_registered(spec.agent, registered) then
      local src = root .. "/tools/" .. spec.src
      local dst = vim.fn.expand(spec.dst)
      if vim.fn.filereadable(src) == 1 then
        json_merge(src, dst, spec.key)
      end
    end
  end

  if is_agent_registered("pi", registered) then
    local pi_ext_dir = vim.fn.expand("~/.pi/agent/extensions/nvim")
    local pi_index = pi_ext_dir .. "/index.ts"
    if vim.fn.isdirectory(pi_ext_dir) == 1 and vim.fn.filereadable(pi_index) == 0 then
      vim.fn.writefile({ 'export { default } from "./dist/pi.js";' }, pi_index)
    end
  end
end

--- Non-blocking install. Skips entirely if stamp is up to date.
--- Everything runs in a single background shell job.
function M.install_async()
  local root = plugin_root()

  -- Fast path: skip if nothing changed (single stat call)
  if is_up_to_date(root) then
    return
  end

  local script = build_install_script(root)

  vim.fn.jobstart({ "sh", "-c", script }, {
    on_exit = vim.schedule_wrap(function(_, code)
      if code ~= 0 then
        vim.notify("Neph: tool install had errors", vim.log.levels.WARN)
      end
      do_json_merges(root)
      touch_stamp()
    end),
  })
end

--- Synchronous install (blocking). Use install_async() for startup.
function M.install()
  local root = plugin_root()
  local script = build_install_script(root)
  vim.fn.system({ "sh", "-c", script })
  do_json_merges(root)
  touch_stamp()
end

return M
