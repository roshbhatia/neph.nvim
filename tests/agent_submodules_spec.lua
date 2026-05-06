local contracts = require("neph.internal.contracts")

describe("neph.agents submodules", function()
  -- Submodule file names (canonical claude/opencode are the peer files).
  local agent_names = {
    "amp",
    "claude-peer",
    "codex",
    "copilot",
    "crush",
    "cursor",
    "gemini",
    "goose",
    "opencode-peer",
    "pi",
  }

  for _, name in ipairs(agent_names) do
    it(name .. " returns a valid AgentDef", function()
      local def = require("neph.agents." .. name)
      assert.has_no.errors(function()
        contracts.validate_agent(def)
      end)
    end)
  end

  -- Hook agents: intercept via cupcake harness or runtime-injected hooks
  local hook_agents = { "copilot", "cursor", "gemini", "pi" }
  for _, name in ipairs(hook_agents) do
    it(name .. " has type = hook", function()
      local def = require("neph.agents." .. name)
      assert.are.equal("hook", def.type)
    end)
  end

  -- Terminal agents: fs_watcher-based interception (no Cupcake hook)
  local terminal_agents = { "amp", "codex", "crush", "goose" }
  for _, name in ipairs(terminal_agents) do
    it(name .. " has type = terminal", function()
      local def = require("neph.agents." .. name)
      assert.are.equal("terminal", def.type)
    end)
  end

  -- Peer agents: delegate session lifecycle to a peer plugin
  local peer_agents = { "claude-peer", "opencode-peer" }
  for _, name in ipairs(peer_agents) do
    it(name .. " has type = peer", function()
      local def = require("neph.agents." .. name)
      assert.are.equal("peer", def.type)
      assert.is_table(def.peer)
      assert.is_string(def.peer.kind)
    end)
  end

  -- Agents with tools manifests
  local agents_with_tools = { "amp" }
  for _, name in ipairs(agents_with_tools) do
    it(name .. " has a valid tools manifest", function()
      local def = require("neph.agents." .. name)
      assert.is_table(def.tools)
      assert.has_no.errors(function()
        contracts.validate_tools(def)
      end)
    end)
  end

  -- Agents without tools (hooks managed via neph CLI or Cupcake native; peer agents own no tools)
  local agents_without_tools = {
    "claude-peer",
    "codex",
    "copilot",
    "crush",
    "cursor",
    "gemini",
    "goose",
    "opencode-peer",
    "pi",
  }
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

  -- Claude (peer): override_diff flag drives diff interception
  describe("claude-peer integration config", function()
    it("requests pre-write diff override", function()
      local def = require("neph.agents.claude-peer")
      assert.is_true(def.peer.override_diff == true)
    end)
  end)

  -- OpenCode (peer): intercept_permissions flag drives permission interception
  describe("opencode-peer integration config", function()
    it("requests permission interception", function()
      local def = require("neph.agents.opencode-peer")
      assert.is_true(def.peer.intercept_permissions == true)
    end)
  end)

  -- Gemini: integration group assignment
  describe("gemini integration config", function()
    it("uses the hook integration group", function()
      local def = require("neph.agents.gemini")
      assert.are.equal("hook", def.integration_group)
      assert.is_nil(def.launch_args_fn)
    end)
  end)

  -- Amp: integration group assignment
  describe("amp integration config", function()
    it("uses the hook integration group", function()
      local def = require("neph.agents.amp")
      assert.are.equal("hook", def.integration_group)
    end)
  end)

  -- Agents with ready_pattern (peer agents have no terminal of their own to match against)
  local agents_with_ready_pattern = { "codex", "crush", "goose" }
  for _, name in ipairs(agents_with_ready_pattern) do
    it(name .. " has a valid ready_pattern", function()
      local def = require("neph.agents." .. name)
      assert.is_string(def.ready_pattern)
      assert.has_no.errors(function()
        contracts.validate_agent(def)
      end)
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
