local raw_path = ...
local edit_path = vim.fn.fnameescape(raw_path)
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
