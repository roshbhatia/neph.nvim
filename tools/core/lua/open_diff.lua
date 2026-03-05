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

local function parse_hunk_ranges(left_lines, right_lines)
  -- vim.diff() expects strings, not tables - join lines with newlines
  local left_str = table.concat(left_lines, "\n")
  local right_str = table.concat(right_lines, "\n")
  
  -- Use vim.diff() to get actual diff hunks
  local ok, diff_result = pcall(vim.diff, left_str, right_str, {
    result_type = "indices",
  })
  
  if not ok or not diff_result then
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

-- ── Parse hunk ranges after diff is set up ───────────────────────────────────

-- Get buffer contents for hunk parsing
local left_lines = vim.api.nvim_buf_get_lines(left_buf, 0, -1, false)
local right_lines = vim.api.nvim_buf_get_lines(right_buf, 0, -1, false)

local hunk_ranges = parse_hunk_ranges(left_lines, right_lines)
local total_hunks = #hunk_ranges

-- ── Sign configuration and setup ──────────────────────────────────────────────

local config = vim.g.neph_config or {}
local signs = vim.tbl_extend("force", {
  accept = "✓",
  reject = "✗",
  current = "→",
  commented = "💬",
}, config.review_signs or {})

vim.fn.sign_define("neph_current",   { text = signs.current,   texthl = "DiagnosticInfo" })
vim.fn.sign_define("neph_accept",    { text = signs.accept,    texthl = "DiagnosticOk" })
vim.fn.sign_define("neph_reject",    { text = signs.reject,    texthl = "DiagnosticError" })
vim.fn.sign_define("neph_commented", { text = signs.commented, texthl = "DiagnosticWarn" })

-- Track sign IDs by line number
local sign_ids = {}

local function place_sign(sign_name, line)
  -- Remove any existing sign on this line first
  if sign_ids[line] then
    vim.fn.sign_unplace("neph_review", { buffer = left_buf, id = sign_ids[line] })
  end
  -- Place new sign and store its ID
  local id = vim.fn.sign_place(0, "neph_review", sign_name, left_buf, { lnum = line, priority = 10 })
  sign_ids[line] = id
end

local function unplace_sign(line)
  if sign_ids[line] then
    vim.fn.sign_unplace("neph_review", { buffer = left_buf, id = sign_ids[line] })
    sign_ids[line] = nil
  end
end

-- ── Virtual text hints ────────────────────────────────────────────────────────

local hints_ns = vim.api.nvim_create_namespace("neph_review_hints")

local function clear_hints()
  vim.api.nvim_buf_clear_namespace(right_buf, hints_ns, 0, -1)
end

local function show_hints(hunk_range, idx)
  clear_hints()
  
  if not hunk_range then return end
  
  local counter_line = hunk_range.start_line - 1 -- 0-indexed
  
  -- Hunk counter at end of hunk start line
  vim.api.nvim_buf_set_extmark(right_buf, hints_ns, counter_line, 0, {
    virt_text = {{ string.format(" ← hunk %d/%d", idx, total_hunks), "DiagnosticInfo" }},
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


-- Check if there are any hunks to review
if total_hunks == 0 then
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


-- Jump to first hunk using ]c motion
vim.api.nvim_set_current_win(left_win)
vim.cmd("normal! gg")  -- Start from top
vim.o.wrapscan = false
pcall(vim.cmd, "normal! ]c")  -- Jump to first diff

hunk_idx = 1
current_hunk_line = hunk_ranges[1].start_line

place_sign("neph_current", current_hunk_line)
show_hints(hunk_ranges[1], 1)

-- ── Interactive review loop using vim.ui.select ──────────────────────────────

local function prompt_hunk_action()
  vim.ui.select(
    { "Accept", "Reject", "Accept all", "Reject all", "Manual edit" },
    {
      prompt = string.format("Hunk %d/%d: ", hunk_idx, total_hunks),
      format_item = function(item) return item end,
    },
    function(choice)
      if not choice then
        -- User cancelled (Esc)
        vim.ui.input({ prompt = "Reject reason: " }, function(reason)
          table.insert(hunks, { index = hunk_idx, decision = "reject", reason = reason or vim.NIL })
          while next_hunk() do
            hunk_idx = hunk_idx + 1
            table.insert(hunks, { index = hunk_idx, decision = "reject", reason = vim.NIL })
          end
          finalize()
        end)
        return
      end
      
      if choice == "Accept" then
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
          prompt_hunk_action()
        else
          finalize()
        end
        
      elseif choice == "Reject" then
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
            prompt_hunk_action()
          else
            finalize()
          end
        end)
        
      elseif choice == "Accept all" then
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
        
      elseif choice == "Reject all" then
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
        
      elseif choice == "Manual edit" then
        table.insert(hunks, { index = hunk_idx, decision = "reject", reason = "Manual resolution" })
        cleanup()
        write_result({
          schema   = "review/v1",
          decision = "reject",
          content  = "",
          hunks    = hunks,
          reason   = "Manual resolution",
        })
      end
    end
  )
end

-- Start the review loop
prompt_hunk_action()
