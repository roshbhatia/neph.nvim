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
-- Error codes and structured results
-- ---------------------------------------------------------------------------

local ERROR_CODES = {
  EPERM = "EPERM",
  ENOENT = "ENOENT",
  BUILD_FAILED = "BUILD_FAILED",
  VALIDATION_FAILED = "VALIDATION_FAILED",
  ECONNREFUSED = "ECONNREFUSED",
}

local function make_error(code, message, remedy)
  return {
    code = code,
    message = message,
    remedy = remedy,
  }
end

-- ---------------------------------------------------------------------------
-- Fingerprint manifest (replaces stamp files)
-- ---------------------------------------------------------------------------

local function manifest_path()
  local state_dir = vim.fn.stdpath("state")
  if not state_dir then
    state_dir = vim.fn.stdpath("data")
  end
  return state_dir .. "/neph/fingerprints.json"
end

local function hash_file(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local content = f:read("*all")
  f:close()
  return vim.fn.sha256(content)
end

local function compute_fingerprint(root, agent, is_universal)
  local fp = { sources = {}, artifacts = {} }

  if is_universal then
    local src_dirs = UNIVERSAL_BUILD.src_dirs
    for _, src_dir in ipairs(src_dirs) do
      local dir_path = root .. "/tools/" .. UNIVERSAL_BUILD.dir .. "/" .. src_dir
      local files = vim.fn.glob(dir_path .. "/**/*.ts", false, true)
      for _, file_path in ipairs(files) do
        local hash = hash_file(file_path)
        if hash then
          local rel_path = file_path:sub(#root + 2)
          fp.sources[rel_path] = hash
        end
      end
    end

    local artifact_path = root .. "/tools/" .. UNIVERSAL_BUILD.dir .. "/" .. UNIVERSAL_BUILD.check
    local artifact_hash = hash_file(artifact_path)
    if artifact_hash then
      local rel_path = artifact_path:sub(#root + 2)
      fp.artifacts[rel_path] = artifact_hash
    end

    return fp
  end

  local tools = agent.tools
  if not tools then
    return fp
  end

  for _, build_spec in ipairs(tools.builds or {}) do
    for _, src_dir in ipairs(build_spec.src_dirs or {}) do
      local dir_path = root .. "/tools/" .. build_spec.dir .. "/" .. src_dir
      local files = vim.fn.glob(dir_path .. "/**/*.ts", false, true)
      for _, file_path in ipairs(files) do
        local hash = hash_file(file_path)
        if hash then
          local rel_path = file_path:sub(#root + 2)
          fp.sources[rel_path] = hash
        end
      end
    end

    local artifact_path = root .. "/tools/" .. build_spec.dir .. "/" .. build_spec.check
    local artifact_hash = hash_file(artifact_path)
    if artifact_hash then
      local rel_path = artifact_path:sub(#root + 2)
      fp.artifacts[rel_path] = artifact_hash
    end
  end

  return fp
end

local function load_manifest()
  local path = manifest_path()
  if vim.fn.filereadable(path) == 0 then
    return {}
  end

  local content = vim.fn.readfile(path)
  if not content or #content == 0 then
    return {}
  end

  local ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
  if not ok or type(data) ~= "table" then
    return {}
  end

  return data
end

local function save_manifest(data)
  local path = manifest_path()
  local dir = vim.fn.fnamemodify(path, ":h")

  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end

  local tmp_path = path .. ".tmp"
  local json_str = vim.json.encode(data)
  vim.fn.writefile({ json_str }, tmp_path)

  local ok, err = os.rename(tmp_path, path)
  if not ok then
    pcall(os.remove, tmp_path)
    error("Failed to save manifest: " .. (err or "unknown error"))
  end
end

local function is_agent_current(manifest, root, agent, is_universal)
  local name = is_universal and UNIVERSAL_NAME or agent.name
  local stored_fp = manifest[name]
  if not stored_fp then
    return false
  end

  local current_fp = compute_fingerprint(root, agent, is_universal)

  for path, hash in pairs(current_fp.sources) do
    if stored_fp.sources[path] ~= hash then
      return false
    end
  end

  for path, hash in pairs(current_fp.artifacts) do
    if stored_fp.artifacts[path] ~= hash then
      return false
    end
  end

  return true
end

-- ---------------------------------------------------------------------------
-- Verification (pre-flight and post-install)
-- ---------------------------------------------------------------------------

local function preflight_checks()
  local missing = {}

  if vim.fn.executable("node") == 0 then
    table.insert(missing, "node")
  end

  if vim.fn.executable("npm") == 0 then
    table.insert(missing, "npm")
  end

  return {
    ok = #missing == 0,
    missing = missing,
  }
end

local function verify_symlink(src, dst)
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
  local target_stat = vim.uv.fs_stat(dst)
  if not target_stat then
    return "broken"
  end
  return "ok"
end

local function verify_build(root, build_spec)
  local artifact_path = root .. "/tools/" .. build_spec.dir .. "/" .. build_spec.check
  return vim.fn.filereadable(artifact_path) == 1
end

local function verify_merge(dst)
  if vim.fn.filereadable(dst) == 0 then
    return false
  end

  local content = vim.fn.readfile(dst)
  if not content or #content == 0 then
    return false
  end

  local ok, _ = pcall(vim.json.decode, table.concat(content, "\n"))
  return ok
end

local function postinstall_validate(root, agent)
  local results = {}
  local t = agent.tools
  if not t then
    return results
  end

  for _, sym in ipairs(t.symlinks or {}) do
    local src = root .. "/tools/" .. sym.src
    local dst = vim.fn.expand(sym.dst)
    local status = verify_symlink(src, dst)
    table.insert(results, {
      type = "symlink",
      path = dst,
      ok = status == "ok",
      status = status,
    })
  end

  for _, build_spec in ipairs(t.builds or {}) do
    local ok = verify_build(root, build_spec)
    table.insert(results, {
      type = "build",
      path = build_spec.dir .. "/" .. build_spec.check,
      ok = ok,
    })
  end

  for _, spec in ipairs(t.merges or {}) do
    local dst = vim.fn.expand(spec.dst)
    local ok = verify_merge(dst)
    table.insert(results, {
      type = "merge",
      path = dst,
      ok = ok,
    })
  end

  return results
end

-- ---------------------------------------------------------------------------
-- Transaction system (atomic install with rollback)
-- ---------------------------------------------------------------------------

local function transaction_dir()
  local state_dir = vim.fn.stdpath("state")
  if not state_dir then
    state_dir = vim.fn.stdpath("data")
  end
  return state_dir .. "/neph/transactions"
end

local function transaction_path(agent_name)
  return transaction_dir() .. "/" .. agent_name .. ".json"
end

local function begin_transaction(agent_name)
  local dir = transaction_dir()
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end

  local tx = {
    agent = agent_name,
    started = os.time(),
    operations = {},
    status = "in_progress",
  }

  local path = transaction_path(agent_name)
  local tmp_path = path .. ".tmp"
  vim.fn.writefile({ vim.json.encode(tx) }, tmp_path)
  local rename_ok, rename_err = os.rename(tmp_path, path)
  if not rename_ok then
    vim.notify("Neph: failed to write transaction: " .. (rename_err or ""), vim.log.levels.WARN)
  end

  return tx
end

local function log_operation(agent_name, op)
  local path = transaction_path(agent_name)
  if vim.fn.filereadable(path) == 0 then
    return
  end

  local content = vim.fn.readfile(path)
  local ok, tx = pcall(vim.json.decode, table.concat(content, "\n"))
  if not ok then
    return
  end

  table.insert(tx.operations, op)

  local tmp_path = path .. ".tmp"
  vim.fn.writefile({ vim.json.encode(tx) }, tmp_path)
  local rename_ok, rename_err = os.rename(tmp_path, path)
  if not rename_ok then
    vim.notify("Neph: failed to log operation: " .. (rename_err or ""), vim.log.levels.WARN)
  end
end

local function commit_transaction(agent_name)
  local path = transaction_path(agent_name)
  if vim.fn.filereadable(path) == 0 then
    return
  end

  local content = vim.fn.readfile(path)
  local ok, tx = pcall(vim.json.decode, table.concat(content, "\n"))
  if not ok then
    return
  end

  tx.status = "complete"
  tx.completed = os.time()

  local tmp_path = path .. ".tmp"
  vim.fn.writefile({ vim.json.encode(tx) }, tmp_path)
  local rename_ok, rename_err = os.rename(tmp_path, path)
  if not rename_ok then
    vim.notify("Neph: failed to commit transaction: " .. (rename_err or ""), vim.log.levels.WARN)
  end

  -- Clean up completed transaction after short delay
  vim.defer_fn(function()
    pcall(os.remove, path)
  end, 1000)
end

local function rollback_transaction(agent_name, tx)
  -- Reverse operations in reverse order
  for i = #tx.operations, 1, -1 do
    local op = tx.operations[i]

    if op.type == "symlink" and op.dst then
      pcall(os.remove, op.dst)
      if op.backup then
        pcall(os.rename, op.backup, op.dst)
      end
    elseif op.type == "merge" and op.backup then
      pcall(os.rename, op.backup, op.dst)
    elseif op.type == "file" and op.dst then
      if op.backup then
        pcall(os.rename, op.backup, op.dst)
      else
        pcall(os.remove, op.dst)
      end
    end
  end

  -- Mark transaction as rolled back
  tx.status = "rolled_back"
  tx.rolled_back_at = os.time()

  local path = transaction_path(agent_name)
  local tmp_path = path .. ".tmp"
  vim.fn.writefile({ vim.json.encode(tx) }, tmp_path)
  local rename_ok, rename_err = os.rename(tmp_path, path)
  if not rename_ok then
    vim.notify("Neph: failed to save rollback state: " .. (rename_err or ""), vim.log.levels.WARN)
  end
end

local function detect_incomplete_transactions()
  local dir = transaction_dir()
  if vim.fn.isdirectory(dir) == 0 then
    return {}
  end

  local incomplete = {}
  local files = vim.fn.glob(dir .. "/*.json", false, true)

  for _, file in ipairs(files) do
    local content = vim.fn.readfile(file)
    if content and #content > 0 then
      local ok, tx = pcall(vim.json.decode, table.concat(content, "\n"))
      if ok and tx.status == "in_progress" then
        table.insert(incomplete, tx)
      end
    end
  end

  return incomplete
end

-- ---------------------------------------------------------------------------
-- Per-agent stamp files (legacy, for backward compat)
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
local function is_agent_up_to_date(root, agent, name)
  local manifest = load_manifest()

  if agent then
    if is_agent_current(manifest, root, agent, false) then
      return true
    end
  elseif name == UNIVERSAL_NAME then
    if is_agent_current(manifest, root, {}, true) then
      return true
    end
  end

  -- Fallback to stamp for backward compat
  local sp = stamp_path(name)
  if vim.fn.filereadable(sp) == 0 then
    return false
  end
  local stamp_content = vim.fn.readfile(sp)
  if not stamp_content or #stamp_content == 0 then
    return false
  end
  return vim.trim(stamp_content[1]) == plugin_version(root)
end

local function touch_stamp(agent, name)
  local root = plugin_root()

  -- Update manifest
  local manifest = load_manifest()
  local fp = compute_fingerprint(root, agent or {}, name == UNIVERSAL_NAME)
  manifest[name] = fp
  pcall(save_manifest, manifest)

  -- Keep legacy stamp for backward compat
  local sp = stamp_path(name)
  vim.fn.writefile({ plugin_version(root) }, sp)
end

local function clear_stamp(name)
  local sp = stamp_path(name)
  pcall(os.remove, sp)
end

-- ---------------------------------------------------------------------------
-- Install locking (PID-based lock files)
-- ---------------------------------------------------------------------------

local function lock_dir()
  local state_dir = vim.fn.stdpath("state")
  if not state_dir then
    state_dir = vim.fn.stdpath("data")
  end
  return state_dir .. "/neph"
end

--- Acquire an exclusive lock for a build name.
---@param name string  lock name (e.g. build dir name)
---@return boolean  true if lock was acquired
function M.acquire_lock(name)
  local dir = lock_dir()
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end

  local path = dir .. "/install-" .. name .. ".lock"

  -- Check for existing lock
  local f = io.open(path, "r")
  if f then
    local pid_str = f:read("*l")
    f:close()
    if pid_str then
      local pid = tonumber(pid_str)
      if pid then
        -- Check if the process is still alive
        local alive = pcall(function()
          local ret = vim.uv.kill(pid, 0)
          if ret ~= 0 and ret ~= true then
            error("dead")
          end
        end)
        if alive then
          return false -- lock held by a live process
        end
        -- Stale lock — remove and retry
        pcall(os.remove, path)
      end
    end
  end

  -- Try exclusive create
  local lf, err = io.open(path, "wx")
  if not lf then
    -- "wx" mode not supported in all Lua versions; fall back
    lf, err = io.open(path, "w")
    if not lf then
      return false
    end
  end
  lf:write(tostring(vim.fn.getpid()))
  lf:close()
  return true
end

--- Release an install lock.
---@param name string  lock name
function M.release_lock(name)
  local path = lock_dir() .. "/install-" .. name .. ".lock"
  local ok, err = os.remove(path)
  if not ok then
    local log = require("neph.internal.log")
    log.debug("tools", "failed to release lock %s: %s", name, tostring(err))
  end
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

  -- Validate destination doesn't escape expected directories
  local resolved_dst = vim.fn.resolve(vim.fn.fnamemodify(dst, ":p"))
  local home = vim.env.HOME or ""
  local root = plugin_root()
  if home ~= "" and resolved_dst:sub(1, #home) ~= home and resolved_dst:sub(1, #root) ~= root then
    return false, "symlink destination escapes allowed directories: " .. dst
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
  local lock_name = build_spec.dir
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

  if not M.acquire_lock(lock_name) then
    callback(false, "could not acquire build lock for " .. lock_name)
    return
  end

  local cmd = string.format("cd %q && npm install --ignore-scripts 2>/dev/null && npm run build 2>&1", tool_dir)
  vim.fn.jobstart({ "sh", "-c", cmd }, {
    on_exit = vim.schedule_wrap(function(_, code)
      M.release_lock(lock_name)
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
  local lock_name = build_spec.dir
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

  if not M.acquire_lock(lock_name) then
    return false, "could not acquire build lock for " .. lock_name
  end

  local cmd = string.format("cd %q && npm install --ignore-scripts 2>/dev/null && npm run build 2>&1", tool_dir)
  local output = vim.fn.system({ "sh", "-c", cmd })
  if vim.v.shell_error ~= 0 then
    M.release_lock(lock_name)
    return false, "npm build failed: " .. (output or "")
  end
  M.release_lock(lock_name)
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
---@param opts? { sync?: boolean, symlink?: boolean }
---@return neph.InstallResult[]
function M.install_universal(root, opts)
  opts = opts or {}
  local results = {}

  -- Symlink is opt-in (skipped during automatic startup install)
  if opts.symlink ~= false then
    local src = root .. "/tools/" .. UNIVERSAL_SYMLINK.src
    local dst = vim.fn.expand(UNIVERSAL_SYMLINK.dst)
    local ok, err = M.install_symlink(src, dst)
    table.insert(results, { op = "symlink", path = dst, ok = ok, err = err })
  end

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
-- Async install (deprecated; use neph CLI)
-- ---------------------------------------------------------------------------

--- Neovim no longer installs integrations; use neph CLI instead.
function M.install_async()
  vim.notify("Neph: install moved to CLI. Use `neph integration`.", vim.log.levels.WARN)
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

  if not is_agent_up_to_date(root, nil, UNIVERSAL_NAME) then
    table.insert(stale, UNIVERSAL_NAME)
  end

  for _, agent in ipairs(agents) do
    if agent.tools and not is_agent_up_to_date(root, agent, agent.name) then
      table.insert(stale, agent.name)
    end
  end

  if #stale > 0 then
    vim.notify(
      "Neph: tools out of date (" .. table.concat(stale, ", ") .. ")\nRun `neph integration toggle`",
      vim.log.levels.WARN
    )
  end
end

--- Synchronous install (deprecated; use neph CLI).
function M.install()
  vim.notify("Neph: install moved to CLI. Use `neph integration`.", vim.log.levels.WARN)
end

-- ---------------------------------------------------------------------------
-- Query helpers
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
