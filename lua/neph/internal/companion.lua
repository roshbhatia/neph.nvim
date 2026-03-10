---@mod neph.companion IDE companion context provider
---@brief [[
--- Collects workspace context (open buffers, cursor, selection) and pushes
--- it to the Gemini companion sidecar via the agent bus.
--- Context updates are debounced and sent as neph:context notifications.
---@brief ]]

local M = {}

local log = require("neph.internal.log")
local bus = require("neph.internal.bus")

---@type userdata|nil debounce timer
local debounce_timer = nil
local DEBOUNCE_MS = 50
local MAX_FILES = 10
local MAX_SELECTED_TEXT = 16384 -- 16KB

---@type integer|nil augroup
local augroup = nil

---@type integer|nil sidecar job ID
local sidecar_job = nil

---@type integer respawn attempt counter
local respawn_attempts = 0
local MAX_RESPAWN_ATTEMPTS = 3

-- ---------------------------------------------------------------------------
-- Context collection
-- ---------------------------------------------------------------------------

---@return table IdeContext payload
function M.collect_context()
  local bufs = vim.api.nvim_list_bufs()
  local current_buf = vim.api.nvim_get_current_buf()
  local files = {}

  for _, buf in ipairs(bufs) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and vim.fn.filereadable(name) == 1 then
        local is_active = buf == current_buf
        local entry = {
          path = name,
          timestamp = os.time(),
          isActive = is_active or nil,
        }

        if is_active then
          local ok, pos = pcall(vim.api.nvim_win_get_cursor, 0)
          if ok then
            entry.cursor = { line = pos[1], character = pos[2] + 1 }
          end

          -- Check for visual selection
          local mode = vim.fn.mode()
          if mode == "v" or mode == "V" or mode == "\22" then
            local ok_sel, sel = pcall(function()
              local start_pos = vim.fn.getpos("v")
              local end_pos = vim.fn.getpos(".")
              local lines = vim.fn.getregion(start_pos, end_pos, { type = mode })
              return table.concat(lines, "\n")
            end)
            if ok_sel and sel and #sel > 0 then
              if #sel > MAX_SELECTED_TEXT then
                sel = sel:sub(1, MAX_SELECTED_TEXT)
              end
              entry.selectedText = sel
            end
          end
        end

        table.insert(files, entry)
      end
    end
  end

  -- Sort by active first, then limit to MAX_FILES
  table.sort(files, function(a, b)
    if a.isActive then
      return true
    end
    if b.isActive then
      return false
    end
    return a.timestamp > b.timestamp
  end)

  if #files > MAX_FILES then
    local trimmed = {}
    for i = 1, MAX_FILES do
      trimmed[i] = files[i]
    end
    files = trimmed
  end

  return {
    workspaceState = {
      openFiles = files,
      isTrusted = true,
    },
  }
end

-- ---------------------------------------------------------------------------
-- Debounced push
-- ---------------------------------------------------------------------------

---@param agent_name string
local function push_context(agent_name)
  if debounce_timer then
    debounce_timer:stop()
  else
    debounce_timer = vim.uv.new_timer()
  end

  debounce_timer:start(
    DEBOUNCE_MS,
    0,
    vim.schedule_wrap(function()
      if not bus.is_connected(agent_name) then
        return
      end
      local context = M.collect_context()
      local ch = bus._get_channels()[agent_name]
      if ch then
        pcall(vim.rpcnotify, ch, "neph:context", context)
      end
    end)
  )
end

-- ---------------------------------------------------------------------------
-- Sidecar lifecycle
-- ---------------------------------------------------------------------------

---@param root string  Plugin root path
---@param workspace string  Workspace path
---@return integer|nil job_id
function M.start_sidecar(root, workspace)
  if sidecar_job then
    return sidecar_job
  end

  respawn_attempts = 0

  local script = root .. "/tools/gemini/dist/companion.js"
  if vim.fn.filereadable(script) ~= 1 then
    vim.notify("Neph: companion sidecar script not found: " .. script, vim.log.levels.ERROR)
    return nil
  end

  local socket = vim.v.servername
  if not socket or socket == "" then
    vim.notify("Neph: no Neovim server socket available for companion sidecar", vim.log.levels.ERROR)
    return nil
  end

  log.debug("companion", "starting sidecar: %s", script)
  sidecar_job = vim.fn.jobstart({ "node", script, workspace }, {
    env = { NVIM_SOCKET_PATH = socket },
    on_exit = vim.schedule_wrap(function(_, code)
      log.debug("companion", "sidecar exited (code=%d)", code)
      sidecar_job = nil
      if code == 0 then
        respawn_attempts = 0
        return
      end
      -- Respawn if unexpected exit and gemini session is still active
      if respawn_attempts >= MAX_RESPAWN_ATTEMPTS then
        vim.notify("Neph: companion sidecar failed after " .. MAX_RESPAWN_ATTEMPTS .. " attempts", vim.log.levels.ERROR)
        return
      end
      respawn_attempts = respawn_attempts + 1
      local delay = 2000 * (2 ^ (respawn_attempts - 1)) -- 2s, 4s, 8s
      log.debug("companion", "respawn attempt %d/%d in %dms", respawn_attempts, MAX_RESPAWN_ATTEMPTS, delay)
      vim.defer_fn(function()
        if not vim.g.gemini_active then
          log.debug("companion", "skipping respawn — gemini no longer active")
          return
        end
        M.start_sidecar(root, workspace)
      end, delay)
    end),
  })

  if sidecar_job <= 0 then
    log.debug("companion", "failed to start sidecar")
    sidecar_job = nil
    return nil
  end

  respawn_attempts = 0
  return sidecar_job
end

function M.stop_sidecar()
  if sidecar_job then
    vim.fn.jobstop(sidecar_job)
    sidecar_job = nil
  end
end

function M.get_sidecar_job()
  return sidecar_job
end

-- ---------------------------------------------------------------------------
-- Autocmd setup
-- ---------------------------------------------------------------------------

---@param agent_name string  The agent name to push context for (e.g., "gemini")
function M.setup_autocmds(agent_name)
  if augroup then
    return
  end

  augroup = vim.api.nvim_create_augroup("NephCompanion", { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold" }, {
    group = augroup,
    callback = function()
      push_context(agent_name)
    end,
  })
end

function M.teardown()
  if augroup then
    vim.api.nvim_del_augroup_by_id(augroup)
    augroup = nil
  end
  if debounce_timer then
    pcall(debounce_timer.stop, debounce_timer)
    pcall(debounce_timer.close, debounce_timer)
    debounce_timer = nil
  end
  M.stop_sidecar()
end

return M
