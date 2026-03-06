--- Generate vimdoc from EmmyLua annotations using mini.doc.
--- Usage: nvim --headless -u NONE -l scripts/docgen.lua

-- Bootstrap mini.doc
local minidoc_path = vim.fn.stdpath("data") .. "/lazy/mini.nvim"
if vim.fn.isdirectory(minidoc_path) == 0 then
  -- Try nix-provided path
  for _, p in ipairs(vim.api.nvim_list_runtime_paths()) do
    if p:match("mini%.nvim") or p:match("mini%-nvim") then
      minidoc_path = p
      break
    end
  end
end
vim.opt.runtimepath:prepend(minidoc_path)

local minidoc = require("mini.doc")
minidoc.setup()

minidoc.generate({
  "lua/neph/rpc.lua",
  "lua/neph/api/status.lua",
  "lua/neph/api/buffers.lua",
  "lua/neph/api/review/engine.lua",
  "lua/neph/api/review/init.lua",
}, "doc/neph.txt")

vim.cmd("qa!")
