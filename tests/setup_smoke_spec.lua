---@diagnostic disable: undefined-global
local helpers = require("tests.test_helpers")

local function make_stub_backend()
  return helpers.make_stub_backend()
end

local function make_valid_agent(name)
  return helpers.make_valid_agent({ name = name or "test" })
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

describe("socket auto-creation", function()
  local neph

  before_each(function()
    package.loaded["neph"] = nil
    package.loaded["neph.init"] = nil
    package.loaded["neph.internal.agents"] = nil
    package.loaded["neph.internal.session"] = nil
    neph = require("neph")
  end)

  it("socket.enable = false skips serverstart", function()
    local called = false
    local orig = vim.fn.serverstart
    vim.fn.serverstart = function(_)
      called = true
      return orig(_)
    end

    neph.setup({
      agents = {},
      backend = make_stub_backend(),
      socket = { enable = false },
    })

    vim.fn.serverstart = orig
    assert.is_false(called)
  end)

  it("socket.enable = true with existing servername skips serverstart", function()
    if vim.v.servername == nil or vim.v.servername == "" then
      return -- nothing to test if no socket exists
    end
    local called = false
    local orig = vim.fn.serverstart
    vim.fn.serverstart = function(_)
      called = true
      return orig(_)
    end

    neph.setup({
      agents = {},
      backend = make_stub_backend(),
      socket = { enable = true },
    })

    vim.fn.serverstart = orig
    assert.is_false(called)
  end)

  it("socket.path is forwarded to serverstart when provided", function()
    if vim.v.servername ~= nil and vim.v.servername ~= "" then
      return -- skip: socket already exists
    end
    local got_path
    local orig = vim.fn.serverstart
    vim.fn.serverstart = function(p)
      got_path = p
      return p
    end

    neph.setup({
      agents = {},
      backend = make_stub_backend(),
      socket = { enable = true, path = "/tmp/neph_test.sock" },
    })

    vim.fn.serverstart = orig
    assert.equals("/tmp/neph_test.sock", got_path)
  end)
end)

describe("setup idempotency with active sessions", function()
  local neph, session_mod

  before_each(function()
    package.loaded["neph"] = nil
    package.loaded["neph.init"] = nil
    package.loaded["neph.internal.agents"] = nil
    package.loaded["neph.internal.session"] = nil
    neph = require("neph")
  end)

  it("second setup with different config does not crash", function()
    local agent_a = make_valid_agent("idem_a")
    local stub = make_stub_backend()

    neph.setup({ agents = { agent_a }, backend = stub })

    assert.has_no.errors(function()
      neph.setup({ agents = { agent_a }, backend = stub, env = { FOO = "bar" } })
    end)
  end)

  it("after second setup old sessions table is empty (no open sessions were created)", function()
    local agent_a = make_valid_agent("idem_b")
    local stub = make_stub_backend()

    neph.setup({ agents = { agent_a }, backend = stub })

    -- Re-setup with a fresh session module reload
    package.loaded["neph.internal.session"] = nil
    neph.setup({ agents = { agent_a }, backend = stub })

    session_mod = require("neph.internal.session")
    local all = session_mod.get_all()
    assert.are.equal(0, vim.tbl_count(all))
  end)

  it("after second setup new sessions can be opened", function()
    local agent_a = make_valid_agent("idem_c")
    local open_count = 0
    local stub = make_stub_backend({
      open = function(_, cfg, _)
        open_count = open_count + 1
        return { pane_id = open_count, cmd = cfg.cmd, cwd = "/tmp", ready = true }
      end,
    })

    neph.setup({ agents = { agent_a }, backend = stub })
    neph.setup({ agents = { agent_a }, backend = stub })

    session_mod = require("neph.internal.session")
    assert.has_no.errors(function()
      session_mod.open("idem_c")
    end)
    assert.are.equal("idem_c", session_mod.get_active())
  end)

  it("config is updated to new values after second setup", function()
    local agent_a = make_valid_agent("idem_d")
    local stub = make_stub_backend()

    neph.setup({ agents = { agent_a }, backend = stub, env = { FIRST = "yes" } })
    neph.setup({ agents = { agent_a }, backend = stub, env = { SECOND = "yes" } })

    local cfg = require("neph.config").current
    assert.are.equal("yes", cfg.env and cfg.env.SECOND)
    assert.is_nil(cfg.env and cfg.env.FIRST)
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

  -- setup() now emits vim.notify(ERROR) and returns early instead of throwing,
  -- so callers do not need pcall.  Each test verifies the notification was
  -- issued and that no partial state was committed.

  it("notifies ERROR and returns without backend", function()
    local notifs, restore = helpers.capture_notifications()
    assert.has_no.errors(function()
      neph.setup({ agents = { make_valid_agent() } })
    end)
    restore()
    helpers.assert_notify(notifs, vim.log.levels.ERROR, "backend")
  end)

  it("notifies ERROR and returns with invalid agent (missing cmd)", function()
    local notifs, restore = helpers.capture_notifications()
    assert.has_no.errors(function()
      neph.setup({
        agents = { { name = "bad", label = "Bad", icon = " " } },
        backend = make_stub_backend(),
      })
    end)
    restore()
    helpers.assert_notify(notifs, vim.log.levels.ERROR, "cmd")
  end)

  it("notifies ERROR and returns with invalid backend (missing methods)", function()
    local notifs, restore = helpers.capture_notifications()
    assert.has_no.errors(function()
      neph.setup({
        agents = { make_valid_agent() },
        backend = { setup = function() end },
      })
    end)
    restore()
    helpers.assert_notify(notifs, vim.log.levels.ERROR, "backend")
  end)

  it("notifies ERROR and returns with malformed tools manifest", function()
    local agent = make_valid_agent()
    agent.tools = { symlinks = { { dst = "~/.foo" } } } -- missing src

    local notifs, restore = helpers.capture_notifications()
    assert.has_no.errors(function()
      neph.setup({
        agents = { agent },
        backend = make_stub_backend(),
      })
    end)
    restore()
    helpers.assert_notify(notifs, vim.log.levels.ERROR, "src")
  end)

  it("notifies ERROR when agents is not a table", function()
    local notifs, restore = helpers.capture_notifications()
    assert.has_no.errors(function()
      neph.setup({
        agents = "not-a-table",
        backend = make_stub_backend(),
      })
    end)
    restore()
    helpers.assert_notify(notifs, vim.log.levels.ERROR, "agents")
  end)

  it("does not commit config when backend is missing", function()
    -- Capture old config state
    local cfg_mod = require("neph.config")
    local old_current = cfg_mod.current
    local notifs, restore = helpers.capture_notifications()

    neph.setup({ agents = { make_valid_agent() } })
    restore()

    -- config.current should not have changed
    assert.are.equal(old_current, cfg_mod.current)
  end)
end)

describe("setup config validation", function()
  local neph

  before_each(function()
    package.loaded["neph"] = nil
    package.loaded["neph.init"] = nil
    package.loaded["neph.internal.agents"] = nil
    package.loaded["neph.internal.session"] = nil
    neph = require("neph")
  end)

  it("warns when file_refresh.interval is zero and falls back to 1000", function()
    local notifs, restore = helpers.capture_notifications()
    assert.has_no.errors(function()
      neph.setup({
        agents = { make_valid_agent("fr_zero") },
        backend = make_stub_backend(),
        file_refresh = { interval = 0 },
      })
    end)
    restore()
    helpers.assert_notify(notifs, vim.log.levels.WARN, "file_refresh.interval")
    local cfg = require("neph.config").current
    assert.are.equal(1000, cfg.file_refresh.interval)
  end)

  it("warns when file_refresh.interval is negative", function()
    local notifs, restore = helpers.capture_notifications()
    assert.has_no.errors(function()
      neph.setup({
        agents = { make_valid_agent("fr_neg") },
        backend = make_stub_backend(),
        file_refresh = { interval = -500 },
      })
    end)
    restore()
    helpers.assert_notify(notifs, vim.log.levels.WARN, "file_refresh.interval")
  end)

  it("accepts a valid positive integer file_refresh.interval", function()
    assert.has_no.errors(function()
      neph.setup({
        agents = { make_valid_agent("fr_ok") },
        backend = make_stub_backend(),
        file_refresh = { interval = 500 },
      })
    end)
    local cfg = require("neph.config").current
    assert.are.equal(500, cfg.file_refresh.interval)
  end)

  it("warns when integration_default_group names a missing group", function()
    local notifs, restore = helpers.capture_notifications()
    assert.has_no.errors(function()
      neph.setup({
        agents = { make_valid_agent("ig_missing") },
        backend = make_stub_backend(),
        integration_default_group = "nonexistent_group",
      })
    end)
    restore()
    helpers.assert_notify(notifs, vim.log.levels.WARN, "integration_default_group")
  end)

  it("does not warn when integration_default_group names a known group", function()
    local notifs, restore = helpers.capture_notifications()
    assert.has_no.errors(function()
      neph.setup({
        agents = { make_valid_agent("ig_ok") },
        backend = make_stub_backend(),
        integration_default_group = "default",
      })
    end)
    restore()
    for _, n in ipairs(notifs) do
      if n.level == vim.log.levels.WARN and n.msg:find("integration_default_group") then
        error("unexpected WARN about integration_default_group: " .. n.msg)
      end
    end
  end)
end)

describe("setup command idempotency", function()
  local neph

  before_each(function()
    package.loaded["neph"] = nil
    package.loaded["neph.init"] = nil
    package.loaded["neph.internal.agents"] = nil
    package.loaded["neph.internal.session"] = nil
    neph = require("neph")
  end)

  it("calling setup() twice does not error on duplicate user commands", function()
    local agent = make_valid_agent("cmd_idem")
    local stub = make_stub_backend()

    neph.setup({ agents = { agent }, backend = stub })

    assert.has_no.errors(function()
      neph.setup({ agents = { agent }, backend = stub })
    end)
  end)
end)
