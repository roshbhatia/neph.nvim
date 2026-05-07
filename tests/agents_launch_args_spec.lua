---@diagnostic disable: undefined-global
-- tests/agents_launch_args_spec.lua
-- Tests for launch_args_fn on agent definitions. Currently only pi has one;
-- the previous claude (terminal/hook) variant was deleted when claude/opencode
-- consolidated to peer-only agents (peer agents have no launch_args_fn).

local function make_temp_root()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. "/tools/pi/dist", "p")
  return root
end

local function cleanup(root)
  vim.fn.delete(root, "rf")
end

describe("pi.launch_args_fn", function()
  local agent

  before_each(function()
    package.loaded["neph.agents.pi"] = nil
    agent = require("neph.agents.pi")
  end)

  it("returns -e and the pi.js path when artifact exists", function()
    local root = make_temp_root()
    vim.fn.writefile({ "// pi.js" }, root .. "/tools/pi/dist/pi.js")
    local ok, args = pcall(agent.launch_args_fn, root)
    cleanup(root)
    assert.is_true(ok)
    assert.is_table(args)
    assert.are.equal("-e", args[1])
    assert.is_string(args[2])
    assert.truthy(args[2]:match("pi%.js$"))
  end)

  it("returns empty table when pi.js is absent", function()
    local root = make_temp_root()
    local ok, args = pcall(agent.launch_args_fn, root)
    cleanup(root)
    assert.is_true(ok)
    assert.is_table(args)
    assert.are.equal(0, #args)
  end)

  it("points to the correct relative path under root", function()
    local root = make_temp_root()
    vim.fn.writefile({ "// pi.js" }, root .. "/tools/pi/dist/pi.js")
    local _, args = pcall(agent.launch_args_fn, root)
    cleanup(root)
    assert.is_table(args)
    assert.truthy(args[2]:find(root, 1, true))
  end)
end)
