-- E2E test runner entry point.
-- Usage: nvim --headless --cmd 'set rtp+=.' -l tests/e2e/run.lua

vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Load snacks.nvim if available (required by neph)
local snacks_path = vim.fn.stdpath("data") .. "/lazy/snacks.nvim"
if vim.fn.isdirectory(snacks_path) == 1 then
  vim.opt.runtimepath:prepend(snacks_path)
end

local harness = dofile(vim.fn.getcwd() .. "/tests/e2e/harness.lua")

-- Discover and run test files (anything matching *_test.lua in tests/e2e/)
local test_dir = vim.fn.getcwd() .. "/tests/e2e"
local test_files = vim.fn.glob(test_dir .. "/*_test.lua", false, true)
table.sort(test_files)

for _, file in ipairs(test_files) do
  local name = vim.fn.fnamemodify(file, ":t:r")
  io.write("\n== " .. name .. " ==\n")
  local run = dofile(file)
  if type(run) == "function" then
    run(harness)
  end
end

local all_passed = harness.report()
if all_passed then
  vim.cmd("qall!")
else
  vim.cmd("cquit 1")
end
