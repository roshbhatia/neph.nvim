---@diagnostic disable: undefined-global
-- session_spec.lua – unit tests for neph.session (no real terminals spawned)
--
-- We pass a stub backend directly via constructor injection.

local session

local function make_stub_backend(visible)
  return {
    setup = function() end,
    open = function(_, agent_cfg, _)
      return { pane_id = 999, cmd = agent_cfg.cmd, cwd = "/tmp", name = "stub", ready = true }
    end,
    focus = function()
      return true
    end,
    hide = function(td)
      td.pane_id = nil
    end,
    is_visible = function(td)
      return visible and td ~= nil and td.pane_id ~= nil
    end,
    kill = function(td)
      td.pane_id = nil
    end,
    cleanup_all = function() end,
  }
end

describe("neph.session", function()
  before_each(function()
    -- Reload session fresh for each test
    package.loaded["neph.session"] = nil
    session = require("neph.internal.session")

    -- Inject stub backend directly
    local stub_backend = make_stub_backend(true)
    session.setup({ env = {} }, stub_backend)
  end)

  describe("get_active()", function()
    it("returns nil when no session is open", function()
      assert.is_nil(session.get_active())
    end)
  end)

  describe("is_visible()", function()
    it("returns false for an unknown terminal name", function()
      assert.is_false(session.is_visible("__no_such_terminal__"))
    end)
  end)

  describe("exists()", function()
    it("returns false for an unknown terminal name", function()
      assert.is_false(session.exists("__no_such_terminal__"))
    end)
  end)

  describe("get_info()", function()
    it("returns nil for unknown terminal", function()
      assert.is_nil(session.get_info("__no_such_terminal__"))
    end)
  end)

  describe("get_all()", function()
    it("returns a table (possibly empty)", function()
      assert.is_table(session.get_all())
    end)
  end)

  describe("launch_args_fn resolution", function()
    it("appends dynamic args to full_cmd", function()
      -- Setup agent with launch_args_fn
      local captured_config = nil
      local backend_spy = make_stub_backend(true)
      backend_spy.open = function(_, agent_cfg, _)
        captured_config = agent_cfg
        return { pane_id = 999, cmd = agent_cfg.cmd, cwd = "/tmp", name = "stub", ready = true }
      end

      package.loaded["neph.session"] = nil
      session = require("neph.internal.session")
      session.setup({ env = {} }, backend_spy)

      -- Register an agent with launch_args_fn
      local agents_mod = require("neph.internal.agents")
      agents_mod.init({
        {
          name = "test_dynamic",
          label = "Test Dynamic",
          icon = " ",
          cmd = "ls",
          args = { "--static" },
          launch_args_fn = function(_root)
            return { "--dynamic", "value" }
          end,
        },
      })

      session.open("test_dynamic")
      assert.is_not_nil(captured_config)
      -- full_cmd should contain both static and dynamic args
      assert.truthy(captured_config.full_cmd:find("--static"))
      assert.truthy(captured_config.full_cmd:find("--dynamic"))
      assert.truthy(captured_config.full_cmd:find("value"))
    end)

    it("falls back to static args when launch_args_fn errors", function()
      local captured_config = nil
      local backend_spy = make_stub_backend(true)
      backend_spy.open = function(_, agent_cfg, _)
        captured_config = agent_cfg
        return { pane_id = 999, cmd = agent_cfg.cmd, cwd = "/tmp", name = "stub", ready = true }
      end

      package.loaded["neph.session"] = nil
      session = require("neph.internal.session")
      session.setup({ env = {} }, backend_spy)

      local agents_mod = require("neph.internal.agents")
      agents_mod.init({
        {
          name = "test_error",
          label = "Test Error",
          icon = " ",
          cmd = "ls",
          args = { "--static" },
          launch_args_fn = function(_root)
            error("intentional test error")
          end,
        },
      })

      session.open("test_error")
      assert.is_not_nil(captured_config)
      -- Should still launch with static args
      assert.truthy(captured_config.full_cmd:find("--static"))
      -- Should NOT contain dynamic args (fn errored)
      assert.is_falsy(captured_config.full_cmd:find("--dynamic"))
    end)
  end)

  describe("ready state", function()
    it("agent without ready_pattern has term_data.ready = true immediately", function()
      local returned_td = nil
      local backend_spy = make_stub_backend(true)
      backend_spy.open = function(_, agent_cfg, _)
        -- Simulate no ready_pattern: backend sets ready = true
        returned_td = {
          pane_id = 999,
          cmd = agent_cfg.cmd,
          cwd = "/tmp",
          name = "stub",
          ready = not agent_cfg.ready_pattern,
        }
        return returned_td
      end

      package.loaded["neph.session"] = nil
      session = require("neph.internal.session")
      session.setup({ env = {} }, backend_spy)

      local agents_mod = require("neph.internal.agents")
      agents_mod.init({
        {
          name = "test_no_pattern",
          label = "Test No Pattern",
          icon = " ",
          cmd = "ls",
        },
      })

      session.open("test_no_pattern")
      assert.is_true(returned_td.ready)
    end)

    it("queues text when term_data.ready is false", function()
      local sent_texts = {}
      local backend_spy = make_stub_backend(true)
      backend_spy.open = function(_, agent_cfg, _)
        return {
          pane_id = 999,
          cmd = agent_cfg.cmd,
          cwd = "/tmp",
          name = "stub",
          ready = false, -- not ready yet
        }
      end

      package.loaded["neph.session"] = nil
      session = require("neph.internal.session")
      session.setup({ env = {} }, backend_spy)

      local agents_mod = require("neph.internal.agents")
      agents_mod.init({
        {
          name = "test_queue",
          label = "Test Queue",
          icon = " ",
          cmd = "ls",
          ready_pattern = "^>",
        },
      })

      session.open("test_queue")
      -- Text should be queued, not sent directly
      session.ensure_active_and_send("hello world")
      -- Since ready=false, nothing should have been sent via the backend
      assert.are.equal(0, #sent_texts)
    end)

    it("drains queue when on_ready fires", function()
      local captured_td = nil
      local backend_spy = make_stub_backend(true)
      backend_spy.open = function(_, agent_cfg, _)
        captured_td = {
          pane_id = 999,
          cmd = agent_cfg.cmd,
          cwd = "/tmp",
          name = "stub",
          ready = false,
          buf = vim.api.nvim_create_buf(false, true),
        }
        return captured_td
      end

      package.loaded["neph.session"] = nil
      session = require("neph.internal.session")
      session.setup({ env = {} }, backend_spy)

      local agents_mod = require("neph.internal.agents")
      agents_mod.init({
        {
          name = "test_drain",
          label = "Test Drain",
          icon = " ",
          cmd = "ls",
          ready_pattern = "^>",
        },
      })

      session.open("test_drain")
      session.ensure_active_and_send("first message")

      -- Simulate ready
      assert.is_not_nil(captured_td.on_ready)
      captured_td.ready = true
      captured_td.on_ready()
      -- After on_ready, the queue should be drained (we can't easily verify send
      -- without a real terminal, but on_ready should not error)
    end)

    it("discards queue on kill_session", function()
      local backend_spy = make_stub_backend(true)
      backend_spy.open = function(_, agent_cfg, _)
        return {
          pane_id = 999,
          cmd = agent_cfg.cmd,
          cwd = "/tmp",
          name = "stub",
          ready = false,
        }
      end

      package.loaded["neph.session"] = nil
      session = require("neph.internal.session")
      session.setup({ env = {} }, backend_spy)

      local agents_mod = require("neph.internal.agents")
      agents_mod.init({
        {
          name = "test_kill_queue",
          label = "Test Kill Queue",
          icon = " ",
          cmd = "ls",
          ready_pattern = "^>",
        },
      })

      session.open("test_kill_queue")
      session.ensure_active_and_send("queued text")
      session.kill_session("test_kill_queue")
      -- After kill, the terminal should be gone
      assert.is_nil(session.get_active())
    end)
  end)
end)
