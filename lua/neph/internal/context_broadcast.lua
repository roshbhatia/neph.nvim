---@mod neph.internal.context_broadcast Continuous editor-state broadcast
---@brief [[
--- Writes a JSON snapshot of the active editor state to
--- vim.fn.stdpath("state") .. "/neph/context.json" on cursor moves, window
--- focus changes, and diagnostic updates. Debounced so rapid events
--- generate at most one write per debounce window.
---
--- Any agent — terminal, hook, peer, extension, or pure CLI tool — can read
--- this file to get fresh editor context without an explicit RPC call.
---
--- Schema is documented in
--- openspec/specs/auto-context-broadcast/spec.md.
---@brief ]]

local M = {}

local context = require("neph.internal.context")
local log = require("neph.internal.log")

---@class neph.ContextBroadcastConfig
---@field enable?           boolean  Enable broadcaster (default: true)
---@field debounce_ms?      integer  Debounce window in ms (default: 50)
---@field include_clipboard? boolean Include +/* register snapshots (default: false; clipboard often holds secrets)

---@type neph.ContextBroadcastConfig
local cfg = { enable = true, debounce_ms = 50, include_clipboard = false }

---@type uv.uv_timer_t|nil
local timer = nil

---@type integer|nil
local augroup_id = nil

---@type string
local target_path = ""

--- Resolve the broadcast file path. Created lazily on first write.
---@return string
local function resolve_target_path()
  if target_path ~= "" then
    return target_path
  end
  local dir = vim.fn.stdpath("state") .. "/neph"
  vim.fn.mkdir(dir, "p")
  target_path = dir .. "/context.json"
  return target_path
end

--- Convert a 0-indexed (line, col) tuple into LSP-shaped position.
---@param line integer  0-indexed
---@param character integer  0-indexed
---@return table
local function pos(line, character)
  return { line = line, character = character }
end

--- Build a `file://` URI from an absolute path. Returns the path unchanged
--- when it is empty so callers can detect "no buffer name" cases.
---@param abs_path string
---@return string
local function to_uri(abs_path)
  if abs_path == nil or abs_path == "" then
    return ""
  end
  return "file://" .. abs_path
end

--- Return true when buf is a regular source buffer that we want to broadcast.
--- Mirrors the source-window filter in context.lua.
---@param buf integer
---@return boolean
local function is_source_buf(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return false
  end
  local bt = vim.bo[buf].buftype
  return bt == "" or bt == "acwrite" or bt == "help"
end

--- Capture the active visual selection (text + LSP-shaped range) for buf,
--- or nil when no visual selection is active.
---@param buf integer
---@return {text:string, range:{start:table, ['end']:table}}|nil
local function capture_selection(buf)
  local range = context.get_selection_range(buf)
  if not range then
    return nil
  end
  -- Convert 1-indexed marks to 0-indexed LSP positions
  local from_line = math.max(0, range.from[1] - 1)
  local to_line = math.max(0, range.to[1] - 1)
  local from_char = range.from[2]
  local to_char = range.to[2]

  local lines = vim.api.nvim_buf_get_lines(buf, from_line, to_line + 1, false)
  if range.kind == "char" and #lines > 0 then
    if #lines == 1 then
      lines[1] = string.sub(lines[1], from_char + 1, to_char + 1)
    else
      lines[1] = string.sub(lines[1], from_char + 1)
      lines[#lines] = string.sub(lines[#lines], 1, to_char + 1)
    end
  end

  return {
    text = table.concat(lines, "\n"),
    range = { start = pos(from_line, from_char), ["end"] = pos(to_line, to_char) },
  }
end

--- Capture all source-buffer URIs that are currently visible across windows
--- (deduped, terminal/float windows skipped).
---@return string[]
local function capture_visible()
  local seen = {}
  local out = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local wcfg = vim.api.nvim_win_get_config(win)
    if wcfg.relative == "" then
      local buf = vim.api.nvim_win_get_buf(win)
      if is_source_buf(buf) then
        local uri = to_uri(vim.api.nvim_buf_get_name(buf))
        if uri ~= "" and not seen[uri] then
          seen[uri] = true
          table.insert(out, uri)
        end
      end
    end
  end
  return out
end

--- Map vim.diagnostic severity numbers to lowercase names.
local SEVERITY_NAME = {
  [vim.diagnostic.severity.ERROR] = "error",
  [vim.diagnostic.severity.WARN] = "warn",
  [vim.diagnostic.severity.INFO] = "info",
  [vim.diagnostic.severity.HINT] = "hint",
}

--- Capture diagnostics keyed by buffer URI. Only includes buffers that are
--- visible to keep the snapshot small.
---@param visible_uris string[]
---@return table<string, table[]>
local function capture_diagnostics(visible_uris)
  local out = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local uri = to_uri(vim.api.nvim_buf_get_name(buf))
    if vim.tbl_contains(visible_uris, uri) and out[uri] == nil then
      local diags = vim.diagnostic.get(buf)
      if #diags > 0 then
        local list = {}
        for _, d in ipairs(diags) do
          table.insert(list, {
            severity = SEVERITY_NAME[d.severity] or "info",
            message = d.message,
            range = {
              start = pos(d.lnum or 0, d.col or 0),
              ["end"] = pos(d.end_lnum or d.lnum or 0, d.end_col or d.col or 0),
            },
          })
        end
        out[uri] = list
      end
    end
  end
  return out
end

--- Build the full broadcast snapshot from current editor state.
---@return table
local function build_snapshot()
  local snapshot = context.capture()
  local buf = snapshot.buf
  local visible = capture_visible()

  local payload = {
    ts = math.floor(vim.uv.hrtime() / 1e6),
    session = vim.v.servername or "",
    cwd = snapshot.cwd or vim.fn.getcwd(),
    visible = visible,
    diagnostics = capture_diagnostics(visible),
  }

  if buf and is_source_buf(buf) then
    local uri = to_uri(vim.api.nvim_buf_get_name(buf))
    payload.buffer = {
      uri = uri,
      language = vim.bo[buf].filetype or "",
      cursor = pos(math.max(0, (snapshot.row or 1) - 1), math.max(0, (snapshot.col or 1) - 1)),
      selection = capture_selection(buf) or vim.NIL,
    }
  end

  if cfg.include_clipboard then
    payload.clipboard = {
      ["+"] = vim.fn.getreg("+"),
      ["*"] = vim.fn.getreg("*"),
    }
  end

  return payload
end

--- Atomically write the snapshot to disk: write to a sibling temp file,
--- then rename. This guarantees readers never observe a partial JSON blob.
---@param payload table
local function write_atomic(payload)
  local target = resolve_target_path()
  local ok_enc, json = pcall(vim.json.encode, payload)
  if not ok_enc then
    log.debug("context_broadcast", "json encode failed: %s", tostring(json))
    return
  end

  local tmp = target .. ".tmp." .. tostring(vim.uv.hrtime())
  local f, ferr = io.open(tmp, "w")
  if not f then
    log.debug("context_broadcast", "open tmp failed: %s", tostring(ferr))
    return
  end
  f:write(json)
  f:close()

  local ok_rename, rename_err = vim.uv.fs_rename(tmp, target)
  if not ok_rename then
    log.debug("context_broadcast", "rename failed: %s", tostring(rename_err))
    -- Best-effort cleanup of the temp file so it doesn't accumulate
    pcall(os.remove, tmp)
  end
end

--- Schedule a write — coalesces bursts into one I/O round per debounce window.
local function schedule_write()
  if not timer then
    return
  end
  -- Reset the timer; if it was already armed, the previous fire is replaced.
  timer:stop()
  timer:start(
    cfg.debounce_ms,
    0,
    vim.schedule_wrap(function()
      local ok, err = pcall(function()
        write_atomic(build_snapshot())
      end)
      if not ok then
        log.debug("context_broadcast", "write failed: %s", tostring(err))
      end
    end)
  )
end

--- Initialise the broadcaster. Idempotent: repeated calls reset autocommands.
---@param opts? neph.ContextBroadcastConfig
function M.setup(opts)
  opts = opts or {}
  if opts.enable ~= nil then
    cfg.enable = opts.enable
  end
  if opts.debounce_ms ~= nil then
    cfg.debounce_ms = math.max(10, opts.debounce_ms)
  end
  if opts.include_clipboard ~= nil then
    cfg.include_clipboard = opts.include_clipboard
  end

  -- Tear down any prior registration so setup() is safe to call again.
  if augroup_id then
    pcall(vim.api.nvim_del_augroup_by_id, augroup_id)
    augroup_id = nil
  end
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end

  if not cfg.enable then
    return
  end

  timer = vim.uv.new_timer()
  augroup_id = vim.api.nvim_create_augroup("NephContextBroadcast", { clear = true })

  vim.api.nvim_create_autocmd({
    "CursorMoved",
    "CursorMovedI",
    "ModeChanged",
    "BufWinEnter",
    "BufWinLeave",
    "WinClosed",
    "WinEnter",
    "DiagnosticChanged",
    "DirChanged",
  }, {
    group = augroup_id,
    callback = schedule_write,
  })

  -- Fire one initial snapshot so the file exists before the first event.
  vim.schedule(function()
    pcall(function()
      write_atomic(build_snapshot())
    end)
  end)
end

--- Return the resolved target path (testing aid).
---@return string
function M._target_path()
  return resolve_target_path()
end

--- Force an immediate (non-debounced) write — testing aid. Respects
--- `cfg.enable`: when the broadcaster is disabled this is a no-op so tests
--- and callers can't accidentally bypass the user's opt-out.
function M._flush_now()
  if not cfg.enable then
    return
  end
  pcall(function()
    write_atomic(build_snapshot())
  end)
end

--- Return current config (testing aid).
---@return neph.ContextBroadcastConfig
function M._config()
  return vim.deepcopy(cfg)
end

return M
