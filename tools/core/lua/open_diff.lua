-- open_diff.lua — Non-blocking diff UI for neph.nvim shim review.
--
-- Called via nvim.exec_lua(LUA_OPEN_DIFF, orig_path, prop_path, result_path, channel_id)
-- Returns immediately after opening the diff tab and registering keymaps.
-- User decisions are handled through buffer-local keymaps which write the
-- ReviewEnvelope JSON to result_path and fire vim.rpcnotify(channel_id, "neph_review_done").

local orig_path, prop_path, result_path, channel_id = ...

local function read_lines(path)
  local lines = {}
  local f = io.open(path, "r")
  if f then
    for line in f:lines() do table.insert(lines, line) end
    f:close()
  end
  return lines
end

local function write_result(envelope)
  local f = assert(io.open(result_path, "w"))
  f:write(vim.json.encode(envelope))
  f:close()
  vim.rpcnotify(channel_id, "neph_review_done")
end

local ft = vim.filetype.match({ filename = orig_path }) or ""
local basename = vim.fn.fnamemodify(orig_path, ":t")

-- ── Open diff tab ─────────────────────────────────────────────────────────────

vim.cmd("tabnew")
local diff_tab = vim.api.nvim_get_current_tabpage()

-- Left: current (editable — user applies hunks here via diffget)
local left_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, read_lines(orig_path))
vim.api.nvim_buf_set_name(left_buf, "[CURRENT] " .. basename)
vim.bo[left_buf].buftype   = "nofile"
vim.bo[left_buf].bufhidden = "wipe"
vim.bo[left_buf].swapfile  = false
vim.bo[left_buf].modified  = false
if ft ~= "" then vim.bo[left_buf].filetype = ft end

local left_win = vim.api.nvim_get_current_win()
vim.wo[left_win].winbar = "%#DiagnosticInfo# CURRENT %* " .. basename
vim.cmd("diffthis")

-- Right: proposed (read-only reference)
vim.cmd("rightbelow vsplit")
local right_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(0, right_buf)
vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, read_lines(prop_path))
vim.api.nvim_buf_set_name(right_buf, "[PROPOSED] " .. basename)
vim.bo[right_buf].buftype    = "nofile"
vim.bo[right_buf].bufhidden  = "wipe"
vim.bo[right_buf].swapfile   = false
vim.bo[right_buf].modifiable = false
if ft ~= "" then vim.bo[right_buf].filetype = ft end

local right_win = vim.api.nvim_get_current_win()
vim.wo[right_win].winbar = "%#DiagnosticWarn# PROPOSED %* " .. basename
vim.cmd("diffthis")

vim.cmd("wincmd =")
vim.cmd("wincmd h") -- focus left (current) window

-- ── State ─────────────────────────────────────────────────────────────────────

local hunks    = {}   -- { index, decision, reason }
local hunk_idx = 0

local function next_hunk()
  local saved = vim.o.wrapscan
  vim.o.wrapscan = false
  local before = vim.api.nvim_win_get_cursor(left_win)
  pcall(vim.cmd, "normal! ]c")
  local after  = vim.api.nvim_win_get_cursor(left_win)
  vim.o.wrapscan = saved
  return before[1] ~= after[1] or before[2] ~= after[2]
end

local function cleanup()
  pcall(vim.api.nvim_win_close, right_win, true)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(diff_tab)) do
    if vim.api.nvim_win_is_valid(w) then
      vim.api.nvim_set_current_win(w)
      pcall(vim.cmd, "diffoff")
    end
  end
  pcall(vim.cmd, "tabclose " .. vim.api.nvim_tabpage_get_number(diff_tab))
end

local function finalize()
  -- Build final content from left buffer (contains accepted hunks)
  local lines   = vim.api.nvim_buf_get_lines(left_buf, 0, -1, false)
  local content = table.concat(lines, "\n")

  local accepted = vim.tbl_filter(function(h) return h.decision == "accept" end, hunks)
  local rejected = vim.tbl_filter(function(h) return h.decision == "reject" end, hunks)

  local decision
  if #rejected == 0 then
    decision = "accept"
  elseif #accepted == 0 then
    decision = "reject"
    content   = ""
  else
    decision = "partial"
  end

  local reasons = {}
  for _, h in ipairs(rejected) do
    if h.reason and h.reason ~= "" then
      table.insert(reasons, h.reason)
    end
  end

  local envelope = {
    schema   = "review/v1",
    decision = decision,
    content  = content,
    hunks    = hunks,
    reason   = #reasons > 0 and table.concat(reasons, "; ") or vim.NIL,
  }

  cleanup()
  write_result(envelope)
end

-- ── Jump to first hunk ────────────────────────────────────────────────────────

-- Go to end of file then wrap-scan to catch diffs starting at line 1
vim.api.nvim_set_current_win(left_win)
local _before = vim.api.nvim_win_get_cursor(left_win)
vim.cmd("normal! G")
vim.o.wrapscan = true
pcall(vim.cmd, "normal! ]c")
vim.o.wrapscan = false
local _after = vim.api.nvim_win_get_cursor(left_win)

-- No diffs — files are identical; accept immediately
if _before[1] == _after[1] and _before[2] == _after[2] then
  local lines = vim.api.nvim_buf_get_lines(left_buf, 0, -1, false)
  cleanup()
  write_result({
    schema   = "review/v1",
    decision = "accept",
    content  = table.concat(lines, "\n"),
    hunks    = {},
    reason   = vim.NIL,
  })
  return
end

hunk_idx = 1

-- ── Keymaps ───────────────────────────────────────────────────────────────────

local map_opts = { nowait = true, noremap = true, silent = true }

-- y — accept current hunk
vim.keymap.set("n", "y", function()
  vim.api.nvim_set_current_win(left_win)
  pcall(vim.cmd, "diffget")
  vim.cmd("diffupdate")
  table.insert(hunks, { index = hunk_idx, decision = "accept", reason = vim.NIL })
  if next_hunk() then
    hunk_idx = hunk_idx + 1
  else
    finalize()
  end
end, vim.tbl_extend("force", map_opts, { buffer = left_buf, desc = "Accept hunk" }))

-- n — reject current hunk (prompts for reason)
vim.keymap.set("n", "n", function()
  vim.api.nvim_set_current_win(left_win)
  vim.ui.input({ prompt = "Reject reason (optional): " }, function(reason)
    table.insert(hunks, { index = hunk_idx, decision = "reject", reason = reason or vim.NIL })
    if next_hunk() then
      hunk_idx = hunk_idx + 1
    else
      finalize()
    end
  end)
end, vim.tbl_extend("force", map_opts, { buffer = left_buf, desc = "Reject hunk" }))

-- a — accept all remaining hunks
vim.keymap.set("n", "a", function()
  vim.api.nvim_set_current_win(left_win)
  pcall(vim.cmd, "diffget")
  vim.cmd("diffupdate")
  table.insert(hunks, { index = hunk_idx, decision = "accept", reason = vim.NIL })
  while next_hunk() do
    hunk_idx = hunk_idx + 1
    pcall(vim.cmd, "diffget")
    vim.cmd("diffupdate")
    table.insert(hunks, { index = hunk_idx, decision = "accept", reason = vim.NIL })
  end
  finalize()
end, vim.tbl_extend("force", map_opts, { buffer = left_buf, desc = "Accept all hunks" }))

-- d / <Esc> — reject all remaining
vim.keymap.set("n", "d", function()
  vim.ui.input({ prompt = "Reject reason: " }, function(reason)
    table.insert(hunks, { index = hunk_idx, decision = "reject", reason = reason or vim.NIL })
    while next_hunk() do
      hunk_idx = hunk_idx + 1
      table.insert(hunks, { index = hunk_idx, decision = "reject", reason = vim.NIL })
    end
    finalize()
  end)
end, vim.tbl_extend("force", map_opts, { buffer = left_buf, desc = "Reject all hunks" }))

vim.keymap.set("n", "<Esc>", function()
  vim.ui.input({ prompt = "Reject reason: " }, function(reason)
    table.insert(hunks, { index = hunk_idx, decision = "reject", reason = reason or vim.NIL })
    while next_hunk() do
      hunk_idx = hunk_idx + 1
      table.insert(hunks, { index = hunk_idx, decision = "reject", reason = vim.NIL })
    end
    finalize()
  end)
end, vim.tbl_extend("force", map_opts, { buffer = left_buf, desc = "Reject all hunks" }))

-- e — hand off for manual edit
vim.keymap.set("n", "e", function()
  table.insert(hunks, { index = hunk_idx, decision = "reject", reason = "Manual resolution" })
  cleanup()
  write_result({
    schema   = "review/v1",
    decision = "reject",
    content  = "",
    hunks    = hunks,
    reason   = "Manual resolution",
  })
end, vim.tbl_extend("force", map_opts, { buffer = left_buf, desc = "Hand off for manual edit" }))
