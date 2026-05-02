---@diagnostic disable: undefined-global
-- tests/agents_launch_args_spec.lua
-- Tests for launch_args_fn on claude and pi agent definitions.

local function make_temp_root(template_json)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. "/tools/claude", "p")
  vim.fn.mkdir(root .. "/tools/pi/dist", "p")
  if template_json then
    vim.fn.writefile({ template_json }, root .. "/tools/claude/settings.json")
  end
  return root
end

local function cleanup(root)
  vim.fn.delete(root, "rf")
end

describe("claude.launch_args_fn", function()
  local agent

  before_each(function()
    -- Fresh require on each test so the function closure is in a known state.
    package.loaded["neph.agents.claude"] = nil
    agent = require("neph.agents.claude")
  end)

  it("returns --settings and a path when template exists", function()
    local template = vim.json.encode({
      hooks = {
        SessionStart = {
          { hooks = { { type = "command", command = "PATH=$HOME/.local/bin:$PATH neph integration hook claude" } } },
        },
      },
    })
    local root = make_temp_root(template)
    local ok, args = pcall(agent.launch_args_fn, root)
    cleanup(root)
    assert.is_true(ok)
    assert.is_table(args)
    assert.are.equal("--settings", args[1])
    assert.is_string(args[2])
    assert.truthy(args[2]:match("claude%.json$"))
  end)

  it("writes a settings file with absolute neph path substituted", function()
    local neph_bin = vim.fn.exepath("neph")
    if neph_bin == "" then
      neph_bin = vim.fn.expand("~/.local/bin/neph")
    end
    local template = vim.json.encode({
      hooks = {
        PreToolUse = {
          {
            matcher = "Edit|Write",
            hooks = { { type = "command", command = "PATH=$HOME/.local/bin:$PATH neph integration hook claude" } },
          },
        },
      },
    })
    local root = make_temp_root(template)
    local _, args = pcall(agent.launch_args_fn, root)
    local settings_path = args and args[2]
    local written = settings_path and vim.fn.filereadable(settings_path) == 1
    local content = written and table.concat(vim.fn.readfile(settings_path), "\n") or ""
    cleanup(root)

    assert.truthy(written, "settings file should be written")
    assert.truthy(content:find(neph_bin, 1, true), "absolute neph path should appear in settings")
    assert.falsy(content:find("PATH=", 1, true), "PATH= prefix should be gone")
  end)

  it("returns empty table when template file is missing", function()
    local root = make_temp_root(nil) -- no template written
    local ok, args = pcall(agent.launch_args_fn, root)
    cleanup(root)
    assert.is_true(ok)
    assert.are.same({}, args)
  end)

  it("returns empty table when template is invalid JSON", function()
    local root = make_temp_root("not valid json {{{")
    local ok, args = pcall(agent.launch_args_fn, root)
    cleanup(root)
    assert.is_true(ok)
    assert.are.same({}, args)
  end)

  it("is idempotent — calling twice produces the same args", function()
    local template = vim.json.encode({
      hooks = {
        SessionStart = {
          {
            hooks = {
              { type = "command", command = "PATH=$HOME/.local/bin:$PATH neph integration hook claude" },
            },
          },
        },
      },
    })
    local root = make_temp_root(template)
    local _, args1 = pcall(agent.launch_args_fn, root)
    local _, args2 = pcall(agent.launch_args_fn, root)
    cleanup(root)
    assert.are.same(args1, args2)
  end)
end)

describe("pi.launch_args_fn", function()
  local agent

  before_each(function()
    package.loaded["neph.agents.pi"] = nil
    agent = require("neph.agents.pi")
  end)

  it("returns -e and the pi.js path when artifact exists", function()
    local root = make_temp_root(nil)
    -- Write a fake pi.js artifact
    vim.fn.writefile({ "// pi extension" }, root .. "/tools/pi/dist/pi.js")
    local ok, args = pcall(agent.launch_args_fn, root)
    cleanup(root)
    assert.is_true(ok)
    assert.are.equal("-e", args[1])
    assert.truthy(args[2]:match("pi%.js$"))
  end)

  it("returns empty table when pi.js is absent", function()
    local root = make_temp_root(nil) -- no pi.js written
    local ok, args = pcall(agent.launch_args_fn, root)
    cleanup(root)
    assert.is_true(ok)
    assert.are.same({}, args)
  end)

  it("points to the correct relative path under root", function()
    local root = make_temp_root(nil)
    vim.fn.writefile({ "// pi extension" }, root .. "/tools/pi/dist/pi.js")
    local _, args = pcall(agent.launch_args_fn, root)
    local expected = root .. "/tools/pi/dist/pi.js"
    cleanup(root)
    assert.are.equal(expected, args[2])
  end)
end)
