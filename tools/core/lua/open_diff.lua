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

-- ── Hunk range parsing ────────────────────────────────────────────────────────

local function parse_hunk_ranges_via_diff(left_lines, right_lines)
  -- Use vim.diff() to get actual diff hunks
  local ok, diff_result = pcall(vim.diff, left_lines, right_lines, {
    result_type = "indices",
  })
  
  if not ok or not diff_result then
    vim.api.nvim_echo({{
      "open_diff: vim.diff() failed: " .. tostring(diff_result), "ErrorMsg"
    }}, true, {})
    return {}
  end
  
  local ranges = {}
  for _, hunk in ipairs(diff_result) do
    -- hunk format: {start_a, count_a, start_b, count_b}
    -- We want hunks in the left buffer (the "a" side)
    local start_line = hunk[1]
    local count = hunk[2]
    if count > 0 then
      table.insert(ranges, { 
        start_line = start_line, 
        end_line = start_line + count - 1 
      })
    end
  end
  
  return ranges
end

local function parse_hunk_ranges(buf, win)
  local ok, result = pcall(function()
    local ranges = {}
    local line_count = vim.api.nvim_buf_line_count(buf)
    
    -- Switch to the window to make diff_hlID() work
    local saved_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(win)
    
    local i = 1
    local hunk_lines_found = 0
    while i <= line_count do
      local hl_id = vim.fn.diff_hlID(i, 1)
      if hl_id > 0 then
        hunk_lines_found = hunk_lines_found + 1
        local start_line = i
        -- Scan forward to find end of this hunk
        while i <= line_count and vim.fn.diff_hlID(i, 1) > 0 do
          i = i + 1
        end
        table.insert(ranges, { start_line = start_line, end_line = i - 1 })
      else
        i = i + 1
      end
    end
    
    -- Debug: log what we found
    if hunk_lines_found == 0 then
      vim.api.nvim_echo({{
        string.format("open_diff: scanned %d lines, found 0 diff highlights", line_count), "WarningMsg"
      }}, true, {})
    end
    
    -- Restore window
    vim.api.nvim_set_current_win(saved_win)
    
    return ranges
  end)
  
  if not ok then
    vim.api.nvim_echo({{
      "open_diff: failed to parse hunk ranges, visual feedback disabled", "WarningMsg"
    }}, true, {})
    vim.api.nvim_echo({{
      "Error: " .. tostring(result), "ErrorMsg"
    }}, true, {})
    return {}
  end
  
  return result
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

-- Force diff computation now that both windows have diffthis set
vim.cmd("diffupdate")
vim.cmd("redraw")  -- Ensure display is updated

-- ── Parse hunk ranges after diff is set up ───────────────────────────────────

-- Force diff computation and verify diff mode is active
vim.cmd("diffupdate")

-- Debug: check if diff mode is actually active
local left_diff = vim.wo[left_win].diff
local right_diff = vim.wo[right_win].diff
if not left_diff or not right_diff then
  vim.api.nvim_echo({{
    string.format("open_diff: diff mode not active! left=%s right=%s", 
                  tostring(left_diff), tostring(right_diff)), "ErrorMsg"
  }}, true, {})
end

-- Debug: show buffer contents to verify they're different
local left_lines = vim.api.nvim_buf_get_lines(left_buf, 0, -1, false)
local right_lines = vim.api.nvim_buf_get_lines(right_buf, 0, -1, false)
vim.api.nvim_echo({{
  string.format("open_diff: left_buf has %d lines, right_buf has %d lines", 
                #left_lines, #right_lines), "DiagnosticInfo"
}}, true, {})

-- Try using vim.diff() first (more reliable than diff_hlID)
local hunk_ranges = parse_hunk_ranges_via_diff(left_lines, right_lines)
local total_hunks = #hunk_ranges

-- If vim.diff() didn't work, fall back to diff_hlID() method
if total_hunks == 0 then
  vim.api.nvim_echo({{
    "open_diff: vim.diff() found 0 hunks, trying diff_hlID() fallback", "WarningMsg"
  }}, true, {})
  hunk_ranges = parse_hunk_ranges(left_buf, left_win)
  total_hunks = #hunk_ranges
end

-- Debug: print hunk info
if total_hunks == 0 then
  vim.api.nvim_echo({{
    "open_diff: no hunks detected (files may be identical or diff not computed)", "WarningMsg"
  }}, true, {})
else
  vim.api.nvim_echo({{
    string.format("open_diff: detected %d hunks", total_hunks), "DiagnosticInfo"
  }}, true, {})
end

-- ── Sign configuration and setup ──────────────────────────────────────────────

local config = vim.g.neph_config or {}
local signs = vim.tbl_extend("force", {
  accept = "✅",
  reject = "❌",
  current = "👉",
  commented = "💬❌",
}, config.review_signs or {})

vim.fn.sign_define("neph_current",   { text = signs.current,   texthl = "DiagnosticInfo" })
vim.fn.sign_define("neph_accept",    { text = signs.accept,    texthl = "DiagnosticOk" })
vim.fn.sign_define("neph_reject",    { text = signs.reject,    texthl = "DiagnosticError" })
vim.fn.sign_define("neph_commented", { text = signs.commented, texthl = "DiagnosticWarn" })

local function place_sign(sign_name, line)
  vim.fn.sign_place(0, "neph_review", sign_name, left_buf, { lnum = line, priority = 10 })
end

local function unplace_sign(line)
  vim.fn.sign_unplace("neph_review", { buffer = left_buf, id = line })
end

-- ── Virtual text hints ────────────────────────────────────────────────────────

local hints_ns = vim.api.nvim_create_namespace("neph_review_hints")
local show_help = false

local function clear_hints()
  vim.api.nvim_buf_clear_namespace(right_buf, hints_ns, 0, -1)
end

local function show_hints(hunk_range, idx)
  clear_hints()
  
  if not hunk_range then return end
  
  local counter_line = hunk_range.start_line - 1 -- 0-indexed
  local hint_line = math.min(counter_line + 1, hunk_range.end_line - 1)
  
  -- Hunk counter at end of first line
  vim.api.nvim_buf_set_extmark(right_buf, hints_ns, counter_line, 0, {
    virt_text = {{ string.format("← hunk %d/%d", idx, total_hunks), "DiagnosticInfo" }},
    virt_text_pos = "eol",
  })
  
  -- Keybinding hints on next line
  local hint_text = show_help
    and "y=accept | n=reject+reason | a=accept-all | d=reject-all | e=manual | [?] hide"
    or  "[y]es [n]o [a]ll [d]eny [e]dit [?]help"
  
  vim.api.nvim_buf_set_extmark(right_buf, hints_ns, hint_line, 0, {
    virt_text = {{ hint_text, "DiagnosticInfo" }},
    virt_text_pos = "eol",
  })
end

-- ── State ─────────────────────────────────────────────────────────────────────

local hunks    = {}   -- { index, decision, reason }
local hunk_idx = 0
local current_hunk_line = nil

local function next_hunk()
  local saved = vim.o.wrapscan
  vim.o.wrapscan = false
  local before = vim.api.nvim_win_get_cursor(left_win)
  pcall(vim.cmd, "normal! ]c")
  local after  = vim.api.nvim_win_get_cursor(left_win)
  vim.o.wrapscan = saved
  
  local moved = before[1] ~= after[1] or before[2] ~= after[2]
  if moved then
    hunk_idx = hunk_idx + 1
    return hunk_ranges[hunk_idx]
  end
  return nil
end

local function cleanup()
  vim.fn.sign_unplace("neph_review", { buffer = left_buf })
  clear_hints()
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
if hunk_ranges[1] then
  current_hunk_line = hunk_ranges[1].start_line
  place_sign("neph_current", current_hunk_line)
  show_hints(hunk_ranges[1], 1)
end

-- ── Keymaps ───────────────────────────────────────────────────────────────────

local map_opts = { nowait = true, noremap = true, silent = true }

-- y — accept current hunk
vim.keymap.set("n", "y", function()
  vim.api.nvim_set_current_win(left_win)
  if current_hunk_line then
    unplace_sign(current_hunk_line)
    place_sign("neph_accept", current_hunk_line)
  end
  pcall(vim.cmd, "diffget")
  vim.cmd("diffupdate")
  table.insert(hunks, { index = hunk_idx, decision = "accept", reason = vim.NIL })
  
  local next_range = next_hunk()
  if next_range then
    current_hunk_line = next_range.start_line
    place_sign("neph_current", current_hunk_line)
    show_hints(next_range, hunk_idx)
  else
    finalize()
  end
end, vim.tbl_extend("force", map_opts, { buffer = left_buf, desc = "Accept hunk" }))

-- n — reject current hunk (prompts for reason)
vim.keymap.set("n", "n", function()
  vim.api.nvim_set_current_win(left_win)
  vim.ui.input({ prompt = "Reject reason (optional): " }, function(reason)
    if current_hunk_line then
      unplace_sign(current_hunk_line)
      if reason and reason ~= "" then
        place_sign("neph_commented", current_hunk_line)
      else
        place_sign("neph_reject", current_hunk_line)
      end
    end
    
    table.insert(hunks, { index = hunk_idx, decision = "reject", reason = reason or vim.NIL })
    
    local next_range = next_hunk()
    if next_range then
      current_hunk_line = next_range.start_line
      place_sign("neph_current", current_hunk_line)
      show_hints(next_range, hunk_idx)
    else
      finalize()
    end
  end)
end, vim.tbl_extend("force", map_opts, { buffer = left_buf, desc = "Reject hunk" }))

-- a — accept all remaining hunks
vim.keymap.set("n", "a", function()
  vim.api.nvim_set_current_win(left_win)
  if current_hunk_line then
    unplace_sign(current_hunk_line)
    place_sign("neph_accept", current_hunk_line)
  end
  pcall(vim.cmd, "diffget")
  vim.cmd("diffupdate")
  table.insert(hunks, { index = hunk_idx, decision = "accept", reason = vim.NIL })
  
  while true do
    local next_range = next_hunk()
    if not next_range then break end
    current_hunk_line = next_range.start_line
    place_sign("neph_accept", current_hunk_line)
    pcall(vim.cmd, "diffget")
    vim.cmd("diffupdate")
    table.insert(hunks, { index = hunk_idx, decision = "accept", reason = vim.NIL })
  end
  finalize()
end, vim.tbl_extend("force", map_opts, { buffer = left_buf, desc = "Accept all hunks" }))

-- d / <Esc> — reject all remaining
local function reject_all()
  vim.ui.input({ prompt = "Reject reason: " }, function(reason)
    if current_hunk_line then
      unplace_sign(current_hunk_line)
      place_sign("neph_reject", current_hunk_line)
    end
    table.insert(hunks, { index = hunk_idx, decision = "reject", reason = reason or vim.NIL })
    
    while true do
      local next_range = next_hunk()
      if not next_range then break end
      current_hunk_line = next_range.start_line
      place_sign("neph_reject", current_hunk_line)
      table.insert(hunks, { index = hunk_idx, decision = "reject", reason = vim.NIL })
    end
    finalize()
  end)
end

vim.keymap.set("n", "d", reject_all, vim.tbl_extend("force", map_opts, { buffer = left_buf, desc = "Reject all hunks" }))
vim.keymap.set("n", "<Esc>", reject_all, vim.tbl_extend("force", map_opts, { buffer = left_buf, desc = "Reject all hunks" }))

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

-- ? — toggle help
vim.keymap.set("n", "?", function()
  show_help = not show_help
  if hunk_ranges[hunk_idx] then
    show_hints(hunk_ranges[hunk_idx], hunk_idx)
  end
end, vim.tbl_extend("force", map_opts, { buffer = left_buf, desc = "Toggle help" }))
