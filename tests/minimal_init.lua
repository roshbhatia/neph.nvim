-- Minimal Neovim init for running tests with busted.
-- Usage: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"

vim.opt.runtimepath:prepend(vim.fn.getcwd()) -- neph.nvim itself

-- If plenary is available locally, add it too
local plenary_path = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.runtimepath:prepend(plenary_path)
end

vim.cmd("runtime plugin/plenary.vim")
