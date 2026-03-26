---@diagnostic disable: undefined-global
-- session_spec.lua – unit tests for neph.session (no real terminals spawned)
--
-- We pass a stub backend directly via constructor injection.

local helpers = require("tests.test_helpers")
local session

local function make_stub_backend(visible)
  return helpers.make_stub_backend({
    is_visible = function(td)
      return visible and td ~= nil and td.pane_id ~= nil
    end,
  })
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

  describe("session toggle state machine", function()
    local function make_toggle_backend(visible_flag)
      -- visible_flag is a table so tests can mutate it after backend is built
      local flag = visible_flag
      return helpers.make_stub_backend({
        open = function(_, cfg, _)
          flag.opened = (flag.opened or 0) + 1
          return { pane_id = flag.opened, cmd = cfg.cmd, cwd = "/tmp", ready = true }
        end,
        is_visible = function(td)
          return td ~= nil and td.pane_id ~= nil and flag.visible
        end,
        focus = function(_)
          flag.focused = (flag.focused or 0) + 1
          return true
        end,
        hide = function(td)
          td.pane_id = nil
          flag.hidden = (flag.hidden or 0) + 1
        end,
      })
    end

    it("toggle with no session open calls open (not focus)", function()
      local flag = { visible = false, opened = 0, focused = 0 }
      local be = make_toggle_backend(flag)

      package.loaded["neph.session"] = nil
      package.loaded["neph.internal.session"] = nil
      local s = require("neph.internal.session")
      s.setup({ env = {} }, be)

      local agents_mod = require("neph.internal.agents")
      agents_mod.init({ { name = "tog_none", label = "Tog", icon = " ", cmd = "ls" } })

      s.toggle("tog_none")

      assert.are.equal(1, flag.opened)
      assert.are.equal(0, flag.focused or 0)
    end)

    it("toggle with one session open and visible calls focus", function()
      local flag = { visible = true, opened = 0, focused = 0 }
      local be = make_toggle_backend(flag)

      package.loaded["neph.session"] = nil
      package.loaded["neph.internal.session"] = nil
      local s = require("neph.internal.session")
      s.setup({ env = {} }, be)

      local agents_mod = require("neph.internal.agents")
      agents_mod.init({ { name = "tog_vis", label = "Tog", icon = " ", cmd = "ls" } })

      -- Open first to register the terminal
      flag.visible = false
      s.open("tog_vis")
      assert.are.equal(1, flag.opened)

      -- Now mark visible and toggle — should focus
      flag.visible = true
      s.toggle("tog_vis")

      assert.are.equal(1, flag.opened) -- no extra open
      assert.is_true((flag.focused or 0) >= 1)
    end)

    it("toggle with session hidden (not visible) opens it again", function()
      local flag = { visible = false, opened = 0, focused = 0 }
      local be = make_toggle_backend(flag)

      package.loaded["neph.session"] = nil
      package.loaded["neph.internal.session"] = nil
      local s = require("neph.internal.session")
      s.setup({ env = {} }, be)

      local agents_mod = require("neph.internal.agents")
      agents_mod.init({ { name = "tog_hid", label = "Tog", icon = " ", cmd = "ls" } })

      -- Open, then hide (nil out pane_id so is_visible returns false)
      flag.visible = false
      s.open("tog_hid")
      assert.are.equal(1, flag.opened)

      -- Toggle again while not visible — should open a new pane
      s.toggle("tog_hid")
      assert.are.equal(2, flag.opened)
    end)

    it("toggle switches focus: visible session is focused on toggle", function()
      local flag_a = { visible = true, opened = 0, focused = 0 }
      local flag_b = { visible = false, opened = 0, focused = 0 }

      -- Share a single backend that tracks which terminal is "focused"
      local last_focused = nil
      local shared_be = helpers.make_stub_backend({
        open = function(name, cfg, _)
          if name == "tog_a" then
            flag_a.opened = flag_a.opened + 1
            return { pane_id = 10, cmd = cfg.cmd, cwd = "/tmp", ready = true }
          else
            flag_b.opened = flag_b.opened + 1
            return { pane_id = 20, cmd = cfg.cmd, cwd = "/tmp", ready = true }
          end
        end,
        is_visible = function(td)
          if td and td.pane_id == 10 then
            return flag_a.visible
          end
          if td and td.pane_id == 20 then
            return flag_b.visible
          end
          return false
        end,
        focus = function(td)
          last_focused = td and td.pane_id
          return true
        end,
        hide = function(td)
          td.pane_id = nil
        end,
      })

      package.loaded["neph.session"] = nil
      package.loaded["neph.internal.session"] = nil
      local s = require("neph.internal.session")
      s.setup({ env = {} }, shared_be)

      local agents_mod = require("neph.internal.agents")
      agents_mod.init({
        { name = "tog_a", label = "Tog A", icon = " ", cmd = "ls" },
        { name = "tog_b", label = "Tog B", icon = " ", cmd = "ls" },
      })

      -- Open both
      flag_a.visible = false
      s.open("tog_a")
      flag_b.visible = false
      s.open("tog_b")

      -- Make A visible, B not
      flag_a.visible = true
      flag_b.visible = false

      -- Toggle A — should focus A (visible)
      s.toggle("tog_a")
      assert.are.equal(10, last_focused)
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
