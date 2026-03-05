local raw_path, proposed_content = ...
local edit_path  = vim.fn.fnameescape(raw_path)
local short_path = vim.fn.fnamemodify(raw_path, ':~:.')

-- next_hunk: cursor-position comparison because :normal! ]c never throws —
-- pcall would always return true and the loop would spin forever.
local function next_hunk()
  local saved  = vim.o.wrapscan
  vim.o.wrapscan = false
  local before = vim.api.nvim_win_get_cursor(0)
  pcall(vim.cmd, 'normal! ]c')
  local after  = vim.api.nvim_win_get_cursor(0)
  vim.o.wrapscan = saved
  return before[1] ~= after[1] or before[2] ~= after[2]
end

-- Open / switch to agent tab; left pane = current file on disk
if vim.g.agent_tab then
  local ok = pcall(vim.cmd, 'tabnext ' .. vim.g.agent_tab)
  if not ok then vim.g.agent_tab = nil end
end
if vim.g.agent_tab then
  vim.cmd('edit ' .. edit_path)
else
  vim.cmd('tabnew ' .. edit_path)
  vim.g.agent_tab = vim.fn.tabpagenr()
end

local left_win = vim.api.nvim_get_current_win()
local left_buf = vim.api.nvim_win_get_buf(left_win)
local ft       = vim.bo.filetype

vim.cmd('diffthis')

-- Right pane: scratch buffer with proposed content (read-only)
local new_buf   = vim.api.nvim_create_buf(false, true)
local new_lines = vim.split(proposed_content, '\n', { plain = true })
vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, new_lines)
vim.bo[new_buf].filetype   = ft
vim.bo[new_buf].modifiable = false
vim.bo[new_buf].buftype    = 'nofile'

vim.cmd('vsplit')
vim.api.nvim_win_set_buf(0, new_buf)
vim.cmd('diffthis')
local right_win = vim.api.nvim_get_current_win()

vim.g.agent_diff_wins = { left_win, right_win }

-- Defined after left_buf/left_win so the closures capture them correctly.

local review_ns = vim.api.nvim_create_namespace('pi_review')
local hunk_num  = 0

-- Inline extmark at the first line of the current hunk so the user can
-- always see which hunk is under review even while the cmdline prompt shows.
local function mark_hunk()
  hunk_num = hunk_num + 1
  vim.api.nvim_buf_clear_namespace(left_buf, review_ns, 0, -1)
  local row = vim.api.nvim_win_get_cursor(left_win)[1] - 1  -- 0-indexed
  vim.api.nvim_buf_set_extmark(left_buf, review_ns, row, 0, {
    virt_text     = { { '▸ ', 'DiagnosticInfo' } },
    virt_text_pos = 'inline',
  })
end

local function cleanup()
  vim.api.nvim_buf_clear_namespace(left_buf, review_ns, 0, -1)
  local wins = vim.g.agent_diff_wins
  if not wins then return end
  vim.g.agent_diff_wins = nil
  for _, w in ipairs(wins) do
    if vim.api.nvim_win_is_valid(w) then
      vim.api.nvim_set_current_win(w)
      pcall(vim.cmd, 'diffoff')
    end
  end
  if vim.api.nvim_win_is_valid(wins[2]) then
    vim.api.nvim_win_close(wins[2], true)
  end
  if vim.api.nvim_win_is_valid(left_win) then
    vim.api.nvim_set_current_win(left_win)
  end
end

-- Idiomatic single-keypress prompt in the cmdline — same pattern as f/t/r/etc.
local function choose()
  vim.api.nvim_echo({
    { 'hunk ' .. hunk_num .. '  ', 'Title'   },
    { 'y',                         'Keyword' }, { ' accept  ', 'Comment' },
    { 'n',                         'Keyword' }, { ' reject  ', 'Comment' },
    { 'a',                         'Keyword' }, { ' all     ', 'Comment' },
    { 'd',                         'Keyword' }, { ' done    ', 'Comment' },
    { 'e',                         'Keyword' }, { ' manual',   'Comment' },
  }, false, {})
  vim.cmd('redraw')
  local ch = vim.fn.getcharstr()
  vim.api.nvim_echo({}, false, {})
  return ch
end

local ESC = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)

-- Jump to first hunk reliably.
-- `]c` from inside a hunk skips to the NEXT one, so starting from `gg`
-- breaks when diffs begin at line 1. Instead: go to end of file, enable
-- wrapscan, then `]c` wraps around to the very first diff.
vim.api.nvim_set_current_win(left_win)
vim.cmd('normal! G')
local _before = vim.api.nvim_win_get_cursor(0)
vim.o.wrapscan = true
pcall(vim.cmd, 'normal! ]c')
vim.o.wrapscan = false
local _after = vim.api.nvim_win_get_cursor(0)

if _before[1] == _after[1] and _before[2] == _after[2] then
  -- cursor didn't move = no diffs exist (files identical)
  cleanup()
  local lines = vim.api.nvim_buf_get_lines(left_buf, 0, -1, false)
  return { decision = 'accept', content = table.concat(lines, '\n') }
end
mark_hunk()

local rejected_notes = {}
local accepted_any   = false
local done           = false

while not done do
  vim.api.nvim_set_current_win(left_win)
  local ch = choose()

  if ch == 'y' then                           -- accept hunk
    pcall(vim.cmd, 'diffget')
    vim.cmd('diffupdate')
    accepted_any = true
    if next_hunk() then mark_hunk() else done = true end

  elseif ch == 'n' then                       -- reject hunk
    local note = vim.fn.input('Reason (optional): ')
    if note ~= '' then table.insert(rejected_notes, note) end
    if next_hunk() then mark_hunk() else done = true end

  elseif ch == 'a' then                       -- accept all remaining
    pcall(vim.cmd, 'diffget')
    vim.cmd('diffupdate')
    accepted_any = true
    while next_hunk() do
      pcall(vim.cmd, 'diffget')
      vim.cmd('diffupdate')
    end
    done = true

  elseif ch == 'd' or ch == ESC then          -- done / reject all remaining
    local reason = vim.fn.input('Reason: ')
    cleanup()
    return {
      decision = 'reject',
      reason   = reason ~= '' and reason or 'Rejected',
    }

  elseif ch == 'e' then                       -- hand off for manual edit
    cleanup()
    return { decision = 'reject', reason = 'Manual resolution' }

  end
  -- unrecognised keys are ignored and the prompt re-shows
end

cleanup()

if not accepted_any then
  return {
    decision = 'reject',
    reason   = #rejected_notes > 0
               and table.concat(rejected_notes, '; ')
               or  'All hunks rejected',
  }
end

local lines  = vim.api.nvim_buf_get_lines(left_buf, 0, -1, false)
local result = { decision = 'accept', content = table.concat(lines, '\n') }
if #rejected_notes > 0 then
  result.reason = table.concat(rejected_notes, '; ')
end
return result
