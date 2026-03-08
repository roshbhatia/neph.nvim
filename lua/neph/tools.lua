---@mod neph.tools Tool installation helpers
---@brief [[
--- Processes agent tool manifests and installs bundled companion tools.
---
--- Uses a stamp file to skip reinstallation when nothing has changed.
--- The stamp records the plugin root mtime; install only runs when
--- the plugin directory is newer than the stamp.
---
--- Agent-specific install specs live on each AgentDef's `tools` field.
--- This module is a generic executor — it contains zero agent names.
---@brief ]]

local M = {}

-- Resolve the plugin root (two levels up from this file: lua/neph/tools.lua → ../../)
local function plugin_root()
  local src = debug.getinfo(1, "S").source
  local file = src:match("^@(.+)$") or src
  return vim.fn.fnamemodify(file, ":h:h:h")
end

-- Universal tool (not associated with any agent)
local UNIVERSAL_BUILD = { dir = "neph-cli", src_dirs = { "src" }, check = "dist/index.js" }
local UNIVERSAL_SYMLINK = { src = "neph-cli/dist/index.js", dst = "~/.local/bin/neph" }

-- ---------------------------------------------------------------------------
-- Stamp file: skip install when nothing changed
-- ---------------------------------------------------------------------------

local STAMP_NAME = "neph_install.stamp"

---@return string
local function stamp_path()
  return vim.fn.stdpath("data") .. "/" .. STAMP_NAME
end

---@param root string
---@return boolean  true if install should be skipped
local function is_up_to_date(root)
  local sp = stamp_path()
  local stamp_mt = vim.fn.getftime(sp)
  if stamp_mt < 0 then
    return false
  end
  local tools_dir = root .. "/tools"
  local tools_mt = vim.fn.getftime(tools_dir)
  return tools_mt <= stamp_mt
end

local function touch_stamp()
  local sp = stamp_path()
  vim.fn.writefile({ tostring(os.time()) }, sp)
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

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
-- Manifest collection
-- ---------------------------------------------------------------------------

--- Collect all tool manifests from injected agents.
---@return table  { symlinks = [], merges = [], builds = [], files = [] }
local function collect_manifests()
  local agents = require("neph.internal.agents").get_all()
  local result = { symlinks = {}, merges = {}, builds = {}, files = {} }

  for _, agent in ipairs(agents) do
    local t = agent.tools
    if t then
      for _, s in ipairs(t.symlinks or {}) do
        table.insert(result.symlinks, s)
      end
      for _, m in ipairs(t.merges or {}) do
        table.insert(result.merges, m)
      end
      for _, b in ipairs(t.builds or {}) do
        table.insert(result.builds, b)
      end
      for _, f in ipairs(t.files or {}) do
        table.insert(result.files, f)
      end
    end
  end

  return result
end

-- ---------------------------------------------------------------------------
-- Install logic
-- ---------------------------------------------------------------------------

---@param root string
---@param manifests table
---@return string
local function build_install_script(root, manifests)
  local lines = { "#!/bin/sh" }

  -- Universal symlink
  local u_src = root .. "/tools/" .. UNIVERSAL_SYMLINK.src
  local u_dst = vim.fn.expand(UNIVERSAL_SYMLINK.dst)
  local u_dir = vim.fn.fnamemodify(u_dst, ":h")
  table.insert(lines, string.format("mkdir -p '%s'", u_dir))
  table.insert(lines, string.format("[ -e '%s' ] && ln -sfn '%s' '%s'", u_src, u_src, u_dst))

  -- Agent symlinks
  for _, sym in ipairs(manifests.symlinks) do
    local src = root .. "/tools/" .. sym.src
    local dst = vim.fn.expand(sym.dst)
    local dst_dir = vim.fn.fnamemodify(dst, ":h")
    table.insert(lines, string.format("mkdir -p '%s'", dst_dir))
    table.insert(lines, string.format("[ -e '%s' ] && ln -sfn '%s' '%s'", src, src, dst))
  end

  -- Universal build
  local all_builds = { UNIVERSAL_BUILD }
  for _, b in ipairs(manifests.builds) do
    table.insert(all_builds, b)
  end

  for _, b in ipairs(all_builds) do
    local tool_dir = root .. "/tools/" .. b.dir
    table.insert(lines, string.format("if [ -f '%s/package.json' ]; then", tool_dir))
    table.insert(lines, string.format("  NEEDS_BUILD=0; CHECK='%s/%s'", tool_dir, b.check))
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

--- JSON merges and file creation (must run on main thread for vim.fn access).
---@param root string
---@param manifests table
local function do_post_install(root, manifests)
  -- Merges
  for _, spec in ipairs(manifests.merges) do
    local src = root .. "/tools/" .. spec.src
    local dst = vim.fn.expand(spec.dst)
    if vim.fn.filereadable(src) == 1 then
      json_merge(src, dst, spec.key)
    end
  end

  -- Files
  for _, f in ipairs(manifests.files) do
    local dst = vim.fn.expand(f.dst)
    local dst_dir = vim.fn.fnamemodify(dst, ":h")
    local mode = f.mode or "create_only"

    if mode == "overwrite" or (mode == "create_only" and vim.fn.filereadable(dst) == 0) then
      if vim.fn.isdirectory(dst_dir) == 0 then
        vim.fn.mkdir(dst_dir, "p")
      end
      vim.fn.writefile({ f.content }, dst)
    end
  end
end

--- Non-blocking install. Skips entirely if stamp is up to date.
function M.install_async()
  local root = plugin_root()

  if is_up_to_date(root) then
    return
  end

  local manifests = collect_manifests()
  local script = build_install_script(root, manifests)

  vim.fn.jobstart({ "sh", "-c", script }, {
    on_exit = vim.schedule_wrap(function(_, code)
      if code ~= 0 then
        vim.notify("Neph: tool install had errors", vim.log.levels.WARN)
      end
      do_post_install(root, manifests)
      touch_stamp()
    end),
  })
end

--- Synchronous install (blocking). Use install_async() for startup.
function M.install()
  local root = plugin_root()
  local manifests = collect_manifests()
  local script = build_install_script(root, manifests)
  vim.fn.system({ "sh", "-c", script })
  do_post_install(root, manifests)
  touch_stamp()
end

return M
