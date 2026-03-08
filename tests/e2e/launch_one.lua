-- Launch a single agent in headless neovim, verify it starts, then exit.
-- Usage: nvim --headless --cmd 'set rtp+=.' -l tests/e2e/launch_one.lua -- <agent_name>
--
-- Exit 0 = success, 1 = failure

vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Load snacks.nvim if available (required by native backend)
local snacks_path = os.getenv("SNACKS_PATH") or (vim.fn.stdpath("data") .. "/lazy/snacks.nvim")
if vim.fn.isdirectory(snacks_path) == 1 then
  vim.opt.runtimepath:prepend(snacks_path)
end

-- Initialize Snacks global if the module is available
local snacks_ok, snacks = pcall(require, "snacks")
if snacks_ok then
  -- Snacks needs setup to register Snacks.terminal
  if type(snacks.setup) == "function" then
    snacks.setup()
  end
end

if not snacks_ok then
  io.stderr:write("snacks.nvim not available — cannot test agent launch (native backend requires it)\n")
  -- Exit 0: this is a skip, not a failure
  vim.cmd("qall!")
  return
end

local agent_name = vim.v.argv[#vim.v.argv]
if not agent_name or agent_name == "" then
  io.stderr:write("No agent name provided\n")
  vim.cmd("cquit 1")
  return
end

-- Setup neph
local ok, err = pcall(function()
  require("neph").setup()
end)
if not ok then
  io.stderr:write("neph.setup() failed: " .. tostring(err) .. "\n")
  vim.cmd("cquit 1")
  return
end

-- Verify agent is registered
local agents = require("neph.internal.agents")
local agent = agents.get_by_name(agent_name)
if not agent then
  io.stderr:write("Agent not available: " .. agent_name .. "\n")
  vim.cmd("cquit 1")
  return
end

-- Open agent session
local session = require("neph.internal.session")
ok, err = pcall(function()
  session.open(agent_name)
end)
if not ok then
  io.stderr:write("session.open() failed: " .. tostring(err) .. "\n")
  vim.cmd("cquit 1")
  return
end

-- Wait briefly to see if neovim survives the launch (the pi crash happened immediately)
-- Use vim.defer_fn to let the event loop process
vim.defer_fn(function()
  -- If we get here, neovim survived the launch
  -- Clean up and exit success
  pcall(function()
    session.kill_session(agent_name)
  end)

  -- Give cleanup a moment
  vim.defer_fn(function()
    vim.cmd("qall!")
  end, 500)
end, 2000)
