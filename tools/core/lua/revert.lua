local raw_path = ...
local wins = vim.g.agent_diff_wins
if wins then
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
end
if vim.g.agent_tab then
  pcall(vim.cmd, 'tabnext ' .. vim.g.agent_tab)
end
vim.cmd('edit! ' .. vim.fn.fnameescape(raw_path))
