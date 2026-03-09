---@mod neph.tools Tool installation helpers
---@brief [[
--- Processes agent tool manifests and installs bundled companion tools.
---
--- Uses per-agent stamp files to skip reinstallation when nothing has changed.
--- Each agent and the universal neph-cli have independent stamps so one
--- failure does not block others.
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
local UNIVERSAL_NAME = "neph-cli"

-- ---------------------------------------------------------------------------
-- Per-agent stamp files
-- ---------------------------------------------------------------------------

---@param name string  agent name or "neph-cli"
---@return string
local function stamp_path(name)
  return vim.fn.stdpath("data") .. "/neph_install_" .. name .. ".stamp"
end

--- Compute a version fingerprint for the tools directory.
--- Uses the plugin directory's git HEAD if available, falls back to tools/ mtime.
---@param root string
---@return string
local function plugin_version(root)
  -- Try git HEAD first (fast: just reads a file)
  local head_file = root .. "/.git/HEAD"
  if vim.fn.filereadable(head_file) == 1 then
    local head = vim.fn.readfile(head_file)
    if head and #head > 0 then
      local ref = head[1]:match("^ref: (.+)$")
      if ref then
        local ref_file = root .. "/.git/" .. ref
        if vim.fn.filereadable(ref_file) == 1 then
          local hash = vim.fn.readfile(ref_file)
          if hash and #hash > 0 then
            return vim.trim(hash[1])
          end
        end
      else
        -- Detached HEAD — the line IS the hash
        return vim.trim(head[1])
      end
    end
  end
  -- Fallback: tools directory mtime
  return tostring(vim.fn.getftime(root .. "/tools"))
end

---@param root string
---@param name string
---@return boolean  true if install should be skipped
local function is_agent_up_to_date(root, name)
  local sp = stamp_path(name)
  if vim.fn.filereadable(sp) == 0 then
    return false
  end
  local content = vim.fn.readfile(sp)
  if not content or #content == 0 then
    return false
  end
  return vim.trim(content[1]) == plugin_version(root)
end

local function touch_stamp(name)
  local root = plugin_root()
  local sp = stamp_path(name)
  vim.fn.writefile({ plugin_version(root) }, sp)
end

local function clear_stamp(name)
  local sp = stamp_path(name)
  pcall(os.remove, sp)
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
---@return boolean ok
---@return string? err
local function json_merge(src_path, dst_path, key)
  local src_content = vim.fn.readfile(src_path)
  if not src_content or #src_content == 0 then
    return false, "source file empty or unreadable: " .. src_path
  end
  local ok_src, src_json = pcall(vim.json.decode, table.concat(src_content, "\n"))
  if not ok_src or not src_json or not src_json[key] then
    return false, "failed to parse source JSON: " .. src_path
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
  return true
end

--- Remove matching hook entries from destination JSON file.
---@param src_path string
---@param dst_path string
---@param key string
---@return boolean ok
---@return string? err
local function json_unmerge(src_path, dst_path, key)
  if vim.fn.filereadable(dst_path) == 0 then
    return true -- nothing to unmerge
  end
  local src_content = vim.fn.readfile(src_path)
  if not src_content or #src_content == 0 then
    return true
  end
  local ok_src, src_json = pcall(vim.json.decode, table.concat(src_content, "\n"))
  if not ok_src or not src_json or not src_json[key] then
    return true
  end

  local dst_content = vim.fn.readfile(dst_path)
  if not dst_content or #dst_content == 0 then
    return true
  end
  local ok_dst, dst_json = pcall(vim.json.decode, table.concat(dst_content, "\n"))
  if not ok_dst or not dst_json or not dst_json[key] then
    return true
  end

  local changed = false
  for event_type, src_entries in pairs(src_json[key]) do
    if dst_json[key][event_type] then
      local kept = {}
      for _, existing in ipairs(dst_json[key][event_type]) do
        local should_remove = false
        for _, src_entry in ipairs(src_entries) do
          if hook_entry_exists({ existing }, src_entry) then
            should_remove = true
            break
          end
        end
        if not should_remove then
          table.insert(kept, existing)
        else
          changed = true
        end
      end
      dst_json[key][event_type] = kept
    end
  end

  if changed then
    vim.fn.writefile({ vim.json.encode(dst_json) }, dst_path)
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Pure Lua install/uninstall operations
-- ---------------------------------------------------------------------------

---@param src string  absolute source path
---@param dst string  absolute destination path
---@return boolean ok
---@return string? err
function M.install_symlink(src, dst)
  local src_exists = vim.fn.filereadable(src) == 1 or vim.fn.isdirectory(src) == 1
  if not src_exists then
    return false, "source does not exist: " .. src
  end

  local dst_dir = vim.fn.fnamemodify(dst, ":h")
  if vim.fn.isdirectory(dst_dir) == 0 then
    vim.fn.mkdir(dst_dir, "p")
  end

  -- Remove existing symlink/file first
  pcall(os.remove, dst)

  -- Try vim.uv.fs_symlink first, fall back to os.execute
  local ok, err = vim.uv.fs_symlink(src, dst)
  if not ok then
    local code = os.execute(string.format("ln -sfn %q %q", src, dst))
    if code ~= 0 then
      return false, "symlink failed: " .. (err or "unknown")
    end
  end
  return true
end

---@param dst string  absolute path to symlink to remove
---@return boolean ok
---@return string? err
function M.uninstall_symlink(dst)
  dst = vim.fn.expand(dst)
  if vim.uv.fs_lstat(dst) then
    local ok, err = os.remove(dst)
    if not ok then
      return false, "failed to remove: " .. (err or "unknown")
    end
  end
  return true
end

---@param root string
---@param build_spec table  { dir, src_dirs, check }
---@param callback fun(ok: boolean, err?: string)
function M.run_build(root, build_spec, callback)
  local tool_dir = root .. "/tools/" .. build_spec.dir
  if vim.fn.filereadable(tool_dir .. "/package.json") == 0 then
    callback(true)
    return
  end

  -- Check if build is needed
  local check_path = tool_dir .. "/" .. build_spec.check
  local needs_build = vim.fn.filereadable(check_path) == 0
  if not needs_build then
    local check_mt = vim.fn.getftime(check_path)
    for _, sd in ipairs(build_spec.src_dirs) do
      local src_dir = tool_dir .. "/" .. sd
      -- Use vim.fn.glob to find newer ts files
      local ts_files = vim.fn.glob(src_dir .. "/**/*.ts", false, true)
      for _, f in ipairs(ts_files) do
        if vim.fn.getftime(f) > check_mt then
          needs_build = true
          break
        end
      end
      if needs_build then
        break
      end
    end
  end

  if not needs_build then
    callback(true)
    return
  end

  local cmd = string.format("cd %q && npm install --ignore-scripts 2>/dev/null && npm run build 2>&1", tool_dir)
  vim.fn.jobstart({ "sh", "-c", cmd }, {
    on_exit = vim.schedule_wrap(function(_, code)
      if code ~= 0 then
        callback(false, "npm build failed (exit " .. code .. ")")
      else
        callback(true)
      end
    end),
  })
end

---@param root string
---@param build_spec table
---@return boolean ok
---@return string? err
function M.run_build_sync(root, build_spec)
  local tool_dir = root .. "/tools/" .. build_spec.dir
  if vim.fn.filereadable(tool_dir .. "/package.json") == 0 then
    return true
  end

  local check_path = tool_dir .. "/" .. build_spec.check
  local needs_build = vim.fn.filereadable(check_path) == 0
  if not needs_build then
    local check_mt = vim.fn.getftime(check_path)
    for _, sd in ipairs(build_spec.src_dirs) do
      local src_dir = tool_dir .. "/" .. sd
      local ts_files = vim.fn.glob(src_dir .. "/**/*.ts", false, true)
      for _, f in ipairs(ts_files) do
        if vim.fn.getftime(f) > check_mt then
          needs_build = true
          break
        end
      end
      if needs_build then
        break
      end
    end
  end

  if not needs_build then
    return true
  end

  local cmd = string.format("cd %q && npm install --ignore-scripts 2>/dev/null && npm run build 2>&1", tool_dir)
  local output = vim.fn.system({ "sh", "-c", cmd })
  if vim.v.shell_error ~= 0 then
    return false, "npm build failed: " .. (output or "")
  end
  return true
end

---@param dst string
---@param content string
---@param mode string  "create_only" or "overwrite"
---@return boolean ok
---@return string? err
local function install_file(dst, content, mode)
  dst = vim.fn.expand(dst)
  mode = mode or "create_only"

  if mode == "create_only" and vim.fn.filereadable(dst) == 1 then
    return true
  end

  local dst_dir = vim.fn.fnamemodify(dst, ":h")
  if vim.fn.isdirectory(dst_dir) == 0 then
    vim.fn.mkdir(dst_dir, "p")
  end
  vim.fn.writefile({ content }, dst)
  return true
end

---@param dst string
---@return boolean ok
local function uninstall_file(dst)
  dst = vim.fn.expand(dst)
  if vim.fn.filereadable(dst) == 1 then
    pcall(os.remove, dst)
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Per-agent install/uninstall
-- ---------------------------------------------------------------------------

---@class neph.InstallResult
---@field op string  "symlink"|"merge"|"build"|"file"
---@field path string
---@field ok boolean
---@field err string?

---@param root string
---@param agent neph.AgentDef
---@param opts? { sync?: boolean }
---@return neph.InstallResult[]
function M.install_agent(root, agent, opts)
  opts = opts or {}
  local t = agent.tools
  if not t then
    return {}
  end

  local results = {}

  -- Symlinks
  for _, sym in ipairs(t.symlinks or {}) do
    local src = root .. "/tools/" .. sym.src
    local dst = vim.fn.expand(sym.dst)
    local ok, err = M.install_symlink(src, dst)
    table.insert(results, { op = "symlink", path = dst, ok = ok, err = err })
  end

  -- Merges
  for _, spec in ipairs(t.merges or {}) do
    local src = root .. "/tools/" .. spec.src
    local dst = vim.fn.expand(spec.dst)
    if vim.fn.filereadable(src) == 1 then
      local ok, err = json_merge(src, dst, spec.key)
      table.insert(results, { op = "merge", path = dst, ok = ok, err = err })
    end
  end

  -- Files
  for _, f in ipairs(t.files or {}) do
    local ok, err = install_file(f.dst, f.content, f.mode)
    table.insert(results, { op = "file", path = vim.fn.expand(f.dst), ok = ok, err = err })
  end

  -- Builds (sync only — async builds are handled separately)
  if opts.sync then
    for _, b in ipairs(t.builds or {}) do
      local ok, err = M.run_build_sync(root, b)
      table.insert(results, { op = "build", path = b.dir, ok = ok, err = err })
    end
  end

  return results
end

---@param root string
---@param agent neph.AgentDef
---@return neph.InstallResult[]
function M.uninstall_agent(root, agent)
  local t = agent.tools
  if not t then
    return {}
  end

  local results = {}

  -- Remove symlinks
  for _, sym in ipairs(t.symlinks or {}) do
    local dst = vim.fn.expand(sym.dst)
    local ok, err = M.uninstall_symlink(dst)
    table.insert(results, { op = "symlink", path = dst, ok = ok, err = err })
  end

  -- Unmerge JSON
  for _, spec in ipairs(t.merges or {}) do
    local src = root .. "/tools/" .. spec.src
    local dst = vim.fn.expand(spec.dst)
    local ok, err = json_unmerge(src, dst, spec.key)
    table.insert(results, { op = "unmerge", path = dst, ok = ok, err = err })
  end

  -- Remove created files
  for _, f in ipairs(t.files or {}) do
    local dst = vim.fn.expand(f.dst)
    uninstall_file(dst)
    table.insert(results, { op = "file", path = dst, ok = true })
  end

  clear_stamp(agent.name)
  return results
end

-- ---------------------------------------------------------------------------
-- Universal neph-cli install/uninstall
-- ---------------------------------------------------------------------------

---@param root string
---@param opts? { sync?: boolean }
---@return neph.InstallResult[]
function M.install_universal(root, opts)
  opts = opts or {}
  local results = {}

  local src = root .. "/tools/" .. UNIVERSAL_SYMLINK.src
  local dst = vim.fn.expand(UNIVERSAL_SYMLINK.dst)
  local ok, err = M.install_symlink(src, dst)
  table.insert(results, { op = "symlink", path = dst, ok = ok, err = err })

  if opts.sync then
    local bok, berr = M.run_build_sync(root, UNIVERSAL_BUILD)
    table.insert(results, { op = "build", path = UNIVERSAL_BUILD.dir, ok = bok, err = berr })
  end

  return results
end

---@param root string
---@return neph.InstallResult[]
function M.uninstall_universal(root)
  local results = {}
  local dst = vim.fn.expand(UNIVERSAL_SYMLINK.dst)
  local ok, err = M.uninstall_symlink(dst)
  table.insert(results, { op = "symlink", path = dst, ok = ok, err = err })
  clear_stamp(UNIVERSAL_NAME)
  return results
end

-- ---------------------------------------------------------------------------
-- Async install (used by :NephTools install all)
-- ---------------------------------------------------------------------------

--- Non-blocking install. Each agent installs independently.
function M.install_async()
  local root = plugin_root()
  local agents = require("neph.internal.agents").get_all()

  -- Universal neph-cli
  if not is_agent_up_to_date(root, UNIVERSAL_NAME) then
    local results = M.install_universal(root)
    local all_ok = true
    for _, r in ipairs(results) do
      if not r.ok then
        all_ok = false
        vim.notify("Neph: " .. UNIVERSAL_NAME .. ": " .. (r.err or "unknown error"), vim.log.levels.WARN)
      end
    end

    -- Async build for neph-cli
    M.run_build(root, UNIVERSAL_BUILD, function(ok, err)
      if ok then
        -- Re-create symlink after build (dist may not have existed before)
        local src = root .. "/tools/" .. UNIVERSAL_SYMLINK.src
        local dst = vim.fn.expand(UNIVERSAL_SYMLINK.dst)
        M.install_symlink(src, dst)
        if all_ok then
          touch_stamp(UNIVERSAL_NAME)
        end
      else
        vim.notify("Neph: " .. UNIVERSAL_NAME .. ": " .. (err or "build failed"), vim.log.levels.WARN)
      end
    end)
  end

  -- Per-agent install
  for _, agent in ipairs(agents) do
    if agent.tools and not is_agent_up_to_date(root, agent.name) then
      local results = M.install_agent(root, agent)
      local agent_ok = true
      for _, r in ipairs(results) do
        if not r.ok then
          agent_ok = false
          vim.notify("Neph: " .. agent.name .. " " .. r.op .. ": " .. (r.err or "unknown error"), vim.log.levels.WARN)
        end
      end

      -- Async builds for this agent
      local builds = agent.tools.builds or {}
      if #builds > 0 then
        local pending = #builds
        local build_ok = true
        for _, b in ipairs(builds) do
          M.run_build(root, b, function(ok, err)
            if not ok then
              build_ok = false
              vim.notify("Neph: " .. agent.name .. " build: " .. (err or "failed"), vim.log.levels.WARN)
            end
            pending = pending - 1
            if pending == 0 and agent_ok and build_ok then
              touch_stamp(agent.name)
            end
          end)
        end
      else
        if agent_ok then
          touch_stamp(agent.name)
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Startup version check (lightweight, no I/O heavy operations)
-- ---------------------------------------------------------------------------

--- Check if tools need reinstalling and notify the user.
--- Does NOT install anything — just reads stamp files and compares versions.
function M.check_version()
  local root = plugin_root()
  local agents = require("neph.internal.agents").get_all()
  local stale = {}

  if not is_agent_up_to_date(root, UNIVERSAL_NAME) then
    table.insert(stale, UNIVERSAL_NAME)
  end

  for _, agent in ipairs(agents) do
    if agent.tools and not is_agent_up_to_date(root, agent.name) then
      table.insert(stale, agent.name)
    end
  end

  if #stale > 0 then
    vim.notify(
      "Neph: tools out of date (" .. table.concat(stale, ", ") .. ")\nRun :NephTools install all",
      vim.log.levels.WARN
    )
  end
end

--- Synchronous install (blocking). Use install_async() for startup.
function M.install()
  local root = plugin_root()
  local agents = require("neph.internal.agents").get_all()

  M.install_universal(root, { sync = true })
  touch_stamp(UNIVERSAL_NAME)

  for _, agent in ipairs(agents) do
    if agent.tools then
      M.install_agent(root, agent, { sync = true })
      touch_stamp(agent.name)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Query helpers (used by NephTools command and checkhealth)
-- ---------------------------------------------------------------------------

--- Get the plugin root path.
---@return string
function M.get_root()
  return plugin_root()
end

--- Get the universal build/symlink specs.
---@return table build_spec, table symlink_spec
function M.get_universal_specs()
  return UNIVERSAL_BUILD, UNIVERSAL_SYMLINK
end

--- Get all registered agents (including those not on PATH).
---@return neph.AgentDef[]
function M.get_all_agents_raw()
  return require("neph.internal.agents").get_all_registered()
end

--- Check if a symlink is valid (exists and points to correct target).
---@param src string  expected target
---@param dst string  symlink path
---@return string  "ok" | "broken" | "missing" | "wrong_target"
function M.check_symlink(src, dst)
  local stat = vim.uv.fs_lstat(dst)
  if not stat then
    return "missing"
  end
  if stat.type ~= "link" then
    return "wrong_target"
  end
  local target = vim.uv.fs_readlink(dst)
  if not target then
    return "broken"
  end
  if target ~= src then
    return "wrong_target"
  end
  -- Check that target actually exists
  local target_stat = vim.uv.fs_stat(dst)
  if not target_stat then
    return "broken"
  end
  return "ok"
end

-- Expose for testing
M._json_merge = json_merge
M._json_unmerge = json_unmerge
M._stamp_path = stamp_path
M._touch_stamp = touch_stamp
M._clear_stamp = clear_stamp

return M
