-- open_diff.lua — Non-blocking diff UI for neph.nvim shim review.
--
-- Called via nvim.exec_lua(LUA_OPEN_DIFF, orig_path, prop_path, result_path, channel_id)
-- Returns immediately after opening the diff tab and registering keymaps.
-- User decisions are handled through buffer-local keymaps which write the
-- ReviewEnvelope JSON to result_path and fire vim.rpcnotify(channel_id, "neph_review_done").

local orig_path, prop_path, result_path, channel_id = ...

-- ── Debug logging ─────────────────────────────────────────────────────────────

local debug_log = io.open("/tmp/neph_review_debug.log", "w")
local function log(msg)
  if debug_log then
    debug_log:write(os.date("%H:%M:%S") .. " " .. msg .. "\n")
    debug_log:flush()
  end
end

log("=== Review session started ===")
log(string.format("orig_path: %s", orig_path))
log(string.format("prop_path: %s", prop_path))
log(string.format("result_path: %s", result_path))
log(string.format("channel_id: %s", tostring(channel_id)))

local function read_lines(path)
  local lines = {}
  local f = io.open(path, "r")
  if f then
    for line in f:lines() do table.insert(lines, line) end
    f:close()
  end
  log(string.format("read_lines(%s): %d lines", path, #lines))
  return lines
end

local function write_result(envelope)
  local f = assert(io.open(result_path, "w"))
  f:write(vim.json.encode(envelope))
  f:close()
  vim.rpcnotify(channel_id, "neph_review_done")
end

-- ── Hunk range parsing ────────────────────────────────────────────────────────

local function parse_hunk_ranges(left_lines, right_lines)
  log(string.format("parse_hunk_ranges: left=%d lines, right=%d lines", #left_lines, #right_lines))
  
  -- Use vim.diff() to get actual diff hunks
  local ok, diff_result = pcall(vim.diff, left_lines, right_lines, {
    result_type = "indices",
  })
  
  if not ok or not diff_result then
    log(string.format("vim.diff failed: ok=%s, result=%s", tostring(ok), tostring(diff_result)))
    return {}
  end
  
  log(string.format("vim.diff returned %d hunks", #diff_result))
  
  local ranges = {}
  for i, hunk in ipairs(diff_result) do
    log(string.format("  hunk[%d]: start_a=%d, count_a=%d, start_b=%d, count_b=%d", 
                      i, hunk[1], hunk[2], hunk[3], hunk[4]))
    -- hunk format: {start_a, count_a, start_b, count_b}
    -- We want hunks in the left buffer (the "a" side)
    local start_line = hunk[1]
    local count = hunk[2]
    if count > 0 then
      table.insert(ranges, { 
        start_line = start_line, 
        end_line = start_line + count - 1 
      })
      log(string.format("  -> range: start_line=%d, end_line=%d", start_line, start_line + count - 1))
    end
  end
  
  log(string.format("parse_hunk_ranges: returning %d ranges", #ranges))
  return ranges
end

local ft = vim.filetype.match({ filename = orig_path }) or ""
local basename = vim.fn.fnamemodify(orig_path, ":t")

-- ── Open diff tab ─────────────────────────────────────────────────────────────

log("Opening new tab for diff")
vim.cmd("tabnew")
local diff_tab = vim.api.nvim_get_current_tabpage()
log(string.format("diff_tab: %d", diff_tab))

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

-- ── Parse hunk ranges after diff is set up ───────────────────────────────────

-- Get buffer contents for hunk parsing
local left_lines = vim.api.nvim_buf_get_lines(left_buf, 0, -1, false)
local right_lines = vim.api.nvim_buf_get_lines(right_buf, 0, -1, false)

log(string.format("About to parse hunks: left_buf=%d, right_buf=%d", left_buf, right_buf))
local hunk_ranges = parse_hunk_ranges(left_lines, right_lines)
local total_hunks = #hunk_ranges
log(string.format("total_hunks: %d", total_hunks))

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
  log(string.format("place_sign(%s, %d) on buf=%d", sign_name, line, left_buf))
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
  log(string.format("show_hints(hunk_range=%s, idx=%d)", 
                    hunk_range and string.format("{%d-%d}", hunk_range.start_line, hunk_range.end_line) or "nil",
                    idx))
  clear_hints()
  
  if not hunk_range then 
    log("show_hints: no hunk_range, returning")
    return 
  end
  
  local counter_line = hunk_range.start_line - 1 -- 0-indexed
  local hint_line = math.min(counter_line + 1, hunk_range.end_line - 1)
  
  log(string.format("show_hints: counter_line=%d, hint_line=%d, right_buf=%d", 
                    counter_line, hint_line, right_buf))
  
  -- Hunk counter at end of first line
  vim.api.nvim_buf_set_extmark(right_buf, hints_ns, counter_line, 0, {
    virt_text = {{ string.format("← hunk %d/%d", idx, total_hunks), "DiagnosticInfo" }},
    virt_text_pos = "eol",
  })
  log("show_hints: placed counter extmark")
  
  -- Keybinding hints on next line
  local hint_text = show_help
    and "y=accept | n=reject+reason | a=accept-all | d=reject-all | e=manual | [?] hide"
    or  "[y]es [n]o [a]ll [d]eny [e]dit [?]help"
  
  vim.api.nvim_buf_set_extmark(right_buf, hints_ns, hint_line, 0, {
    virt_text = {{ hint_text, "DiagnosticInfo" }},
    virt_text_pos = "eol",
  })
  log("show_hints: placed hint extmark")
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

log("=== Jump to first hunk section ===")
log(string.format("total_hunks = %d", total_hunks))

-- Check if there are any hunks to review
if total_hunks == 0 then
  log("No hunks detected, auto-accepting")
  -- No diffs — files are identical; accept immediately
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

log("Hunks detected, setting up review UI")

-- Jump to first hunk using ]c motion
vim.api.nvim_set_current_win(left_win)
vim.cmd("normal! gg")  -- Start from top
vim.o.wrapscan = false
pcall(vim.cmd, "normal! ]c")  -- Jump to first diff

hunk_idx = 1
current_hunk_line = hunk_ranges[1].start_line
log(string.format("Setting up first hunk: idx=%d, line=%d", hunk_idx, current_hunk_line))

place_sign("neph_current", current_hunk_line)
show_hints(hunk_ranges[1], 1)

log("=== Initial setup complete ===")
if debug_log then debug_log:close() end

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
