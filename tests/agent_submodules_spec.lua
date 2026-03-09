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

  local agents_with_tools = { "amp", "claude", "cursor", "gemini", "opencode", "pi" }
  for _, name in ipairs(agents_with_tools) do
    it(name .. " has a valid tools manifest", function()
      local def = require("neph.agents." .. name)
      assert.is_table(def.tools)
      assert.has_no.errors(function()
        contracts.validate_tools(def)
      end)
    end)
  end

  local agents_without_tools = { "codex", "copilot", "crush", "goose" }
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
