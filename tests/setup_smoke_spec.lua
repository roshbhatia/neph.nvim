---@diagnostic disable: undefined-global
local contracts = require("neph.internal.contracts")

local function make_stub_backend()
  return {
    setup = function() end,
    open = function(_, agent_cfg, _)
      return { pane_id = 999, cmd = agent_cfg.cmd, cwd = "/tmp", name = "stub" }
    end,
    focus = function() return true end,
    hide = function(td) td.pane_id = nil end,
    is_visible = function(td) return td ~= nil and td.pane_id ~= nil end,
    kill = function(td) td.pane_id = nil end,
    cleanup_all = function() end,
  }
end

local function make_valid_agent(name)
  return { name = name or "test", label = "Test", icon = " ", cmd = "ls", args = {} }
end

describe("setup smoke tests", function()
  local neph, agents

  before_each(function()
    -- Clear cached modules
    package.loaded["neph"] = nil
    package.loaded["neph.init"] = nil
    package.loaded["neph.internal.agents"] = nil
    package.loaded["neph.internal.session"] = nil
    neph = require("neph")
    agents = require("neph.internal.agents")
  end)

  it("wires agents and backend correctly", function()
    local agent_a = make_valid_agent("agent_a")
    local agent_b = make_valid_agent("agent_b")
    agent_b.cmd = "__nonexistent__"

    assert.has_no.errors(function()
      neph.setup({
        agents = { agent_a, agent_b },
        backend = make_stub_backend(),
      })
    end)

    -- agent_a (ls) should be available, agent_b should not
    local all = agents.get_all()
    assert.are.equal(1, #all)
    assert.are.equal("agent_a", all[1].name)
  end)

  it("setup with real agent submodules works", function()
    -- Use a few real agent submodules
    local claude = require("neph.agents.claude")
    local goose = require("neph.agents.goose")

    assert.has_no.errors(function()
      neph.setup({
        agents = { claude, goose },
        backend = make_stub_backend(),
      })
    end)
  end)

  it("setup with agent that has tools manifest works", function()
    local pi = require("neph.agents.pi")

    assert.has_no.errors(function()
      neph.setup({
        agents = { pi },
        backend = make_stub_backend(),
      })
    end)
  end)
end)

describe("setup negative paths", function()
  local neph

  before_each(function()
    package.loaded["neph"] = nil
    package.loaded["neph.init"] = nil
    package.loaded["neph.internal.agents"] = nil
    package.loaded["neph.internal.session"] = nil
    neph = require("neph")
  end)

  it("throws without backend", function()
    assert.has_error(function()
      neph.setup({ agents = { make_valid_agent() } })
    end)
  end)

  it("throws with invalid agent (missing cmd)", function()
    assert.has_error(function()
      neph.setup({
        agents = { { name = "bad", label = "Bad", icon = " " } },
        backend = make_stub_backend(),
      })
    end)
  end)

  it("throws with invalid backend (missing methods)", function()
    assert.has_error(function()
      neph.setup({
        agents = { make_valid_agent() },
        backend = { setup = function() end },
      })
    end)
  end)

  it("throws with malformed tools manifest", function()
    local agent = make_valid_agent()
    agent.tools = { symlinks = { { dst = "~/.foo" } } } -- missing src

    assert.has_error(function()
      neph.setup({
        agents = { agent },
        backend = make_stub_backend(),
      })
    end)
  end)
end)
