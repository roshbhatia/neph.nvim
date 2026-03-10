local contracts = require("neph.internal.contracts")

describe("neph.agents submodules", function()
  local agent_names = { "amp", "claude", "codex", "copilot", "crush", "cursor", "gemini", "goose", "opencode", "pi" }

  for _, name in ipairs(agent_names) do
    it(name .. " returns a valid AgentDef", function()
      local def = require("neph.agents." .. name)
      assert.has_no.errors(function()
        contracts.validate_agent(def)
      end)
      assert.are.equal(name, def.name)
    end)
  end

  local extension_agents = { "amp", "gemini", "opencode", "pi" }
  for _, name in ipairs(extension_agents) do
    it(name .. " has type = extension", function()
      local def = require("neph.agents." .. name)
      assert.are.equal("extension", def.type)
    end)
  end

  local hook_agents = { "claude", "copilot", "cursor" }
  for _, name in ipairs(hook_agents) do
    it(name .. " has type = hook", function()
      local def = require("neph.agents." .. name)
      assert.are.equal("hook", def.type)
    end)
  end

  local terminal_agents = { "codex", "crush", "goose" }
  for _, name in ipairs(terminal_agents) do
    it(name .. " has no type field", function()
      local def = require("neph.agents." .. name)
      assert.is_nil(def.type)
    end)
  end

  local agents_with_tools = { "amp", "cursor", "gemini", "opencode", "pi" }
  for _, name in ipairs(agents_with_tools) do
    it(name .. " has a valid tools manifest", function()
      local def = require("neph.agents." .. name)
      assert.is_table(def.tools)
      assert.has_no.errors(function()
        contracts.validate_tools(def)
      end)
    end)
  end

  local agents_without_tools = { "claude", "codex", "copilot", "crush", "goose" }
  for _, name in ipairs(agents_without_tools) do
    it(name .. " has no tools field", function()
      local def = require("neph.agents." .. name)
      assert.is_nil(def.tools)
    end)
  end

  -- No agent should have removed fields
  for _, name in ipairs(agent_names) do
    it(name .. " has no send_adapter or integration field", function()
      local def = require("neph.agents." .. name)
      assert.is_nil(def.send_adapter)
      assert.is_nil(def.integration)
    end)
  end

  -- Claude: runtime settings injection via launch_args_fn (no tools.merges)
  describe("claude runtime config", function()
    it("has launch_args_fn and no tools.merges", function()
      local def = require("neph.agents.claude")
      assert.is_function(def.launch_args_fn)
      assert.is_nil(def.tools)
    end)

    it("launch_args_fn returns --settings with valid JSON", function()
      local def = require("neph.agents.claude")
      local args = def.launch_args_fn("/fake/root")
      assert.are.equal(2, #args)
      assert.are.equal("--settings", args[1])
      -- Verify the JSON is parseable
      local ok, parsed = pcall(vim.json.decode, args[2])
      assert.is_true(ok, "launch_args_fn JSON must be valid")
      assert.is_table(parsed.hooks)
      assert.is_table(parsed.hooks.PreToolUse)
    end)

    it("launch_args_fn hook command uses absolute path to neph-cli", function()
      local def = require("neph.agents.claude")
      local args = def.launch_args_fn("/test/neph.nvim")
      local parsed = vim.json.decode(args[2])
      local hook_cmd = parsed.hooks.PreToolUse[1].hooks[1].command
      assert.truthy(hook_cmd:find("/test/neph.nvim/tools/neph%-cli/dist/index.js", 1, false))
      assert.truthy(hook_cmd:find("^node "))
    end)
  end)

  -- Agents with launch_args_fn
  local agents_with_launch_args = { "claude" }
  for _, name in ipairs(agents_with_launch_args) do
    it(name .. " has a valid launch_args_fn", function()
      local def = require("neph.agents." .. name)
      assert.is_function(def.launch_args_fn)
      local ok, result = pcall(def.launch_args_fn, "/fake/root")
      assert.is_true(ok, "launch_args_fn must not error")
      assert.is_table(result, "launch_args_fn must return a table")
    end)
  end

  it("all.lua returns all 10 agents", function()
    local all = require("neph.agents.all")
    assert.are.equal(10, #all)
  end)

  it("all.lua entries all pass validation", function()
    local all = require("neph.agents.all")
    for _, def in ipairs(all) do
      assert.has_no.errors(function()
        contracts.validate_agent(def)
      end)
    end
  end)
end)
