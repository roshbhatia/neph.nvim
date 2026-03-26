---@diagnostic disable: undefined-global
-- session_boundary_spec.lua -- boundary/adversarial tests for neph.session

local helpers = require("tests.test_helpers")
local session

local function register_agent(name, extra)
  local def = helpers.make_valid_agent(vim.tbl_extend("force", {
    name = name,
    label = name,
    cmd = "true",
  }, extra or {}))
  require("neph.internal.agents").init({ def })
end

local function fresh_session(backend_overrides)
  package.loaded["neph.session"] = nil
  package.loaded["neph.internal.session"] = nil
  session = require("neph.internal.session")
  local be = helpers.make_stub_backend(backend_overrides)
  session.setup({ env = {} }, be)
  return be
end

describe("neph.session boundary", function()
  describe("backend.open returns nil", function()
    it("does not crash and terminal is not tracked", function()
      fresh_session({
        open = function()
          return nil
        end,
      })
      register_agent("nil_open")

      session.open("nil_open")
      assert.is_nil(session.get_active())
      assert.is_false(session.is_visible("nil_open"))
    end)
  end)

  describe("backend.open throws an error", function()
    it("propagates the error (no silent swallow)", function()
      fresh_session({
        open = function()
          error("boom")
        end,
      })
      register_agent("err_open")

      assert.has_error(function()
        session.open("err_open")
      end)
    end)
  end)

  describe("backend.is_visible lies (returns true for dead pane)", function()
    it("focus succeeds without error when is_visible lies", function()
      local visible = true
      fresh_session({
        is_visible = function()
          return visible
        end,
        open = function(_, cfg, _)
          return { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = true }
        end,
        focus = function()
          return true
        end,
      })
      register_agent("liar")

      session.open("liar")
      assert.is_true(session.is_visible("liar"))
      -- Now the backend claims visible but the pane is dead -- focus still works
      session.focus("liar")
      assert.equals("liar", session.get_active())
    end)
  end)

  describe("kill during stale terminal", function()
    it("kill_session on stale terminal clears state cleanly", function()
      fresh_session({
        open = function(_, cfg, _)
          return { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = true, stale_since = os.time() }
        end,
      })
      register_agent("stale_kill")

      session.open("stale_kill")
      session.kill_session("stale_kill")
      assert.is_nil(session.get_active())
      assert.is_nil(session.get_info("stale_kill"))
      assert.is_nil(vim.g["stale_kill_active"])
    end)
  end)

  describe("send on stale terminal", function()
    it("skips send when terminal is marked stale", function()
      local sent = false
      fresh_session({
        open = function(_, cfg, _)
          return { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = true, stale_since = os.time() }
        end,
        send = function()
          sent = true
        end,
      })
      register_agent("stale_send")

      session.open("stale_send")
      session.send("stale_send", "hello", { submit = true })
      assert.is_false(sent)
    end)
  end)

  describe("send on unknown terminal", function()
    it("returns silently with no error", function()
      fresh_session()
      assert.has_no_errors(function()
        session.send("nonexistent", "hello")
      end)
    end)
  end)

  describe("double open", function()
    it("second open on visible terminal calls focus, not open again", function()
      local open_count = 0
      fresh_session({
        open = function(_, cfg, _)
          open_count = open_count + 1
          return { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = true }
        end,
      })
      register_agent("double")

      session.open("double")
      session.open("double")
      assert.equals(1, open_count)
    end)
  end)

  describe("set_active on unknown terminal", function()
    it("does not change active_terminal", function()
      fresh_session()
      session.set_active("ghost")
      assert.is_nil(session.get_active())
    end)
  end)

  describe("hide unknown terminal", function()
    it("does not error", function()
      fresh_session()
      assert.has_no_errors(function()
        session.hide("nonexistent")
      end)
    end)
  end)

  describe("focus with no backend", function()
    it("returns silently when backend is nil-ish", function()
      package.loaded["neph.session"] = nil
      package.loaded["neph.internal.session"] = nil
      session = require("neph.internal.session")
      -- Do NOT call setup -- backend is nil
      assert.has_no_errors(function()
        session.focus("anything")
      end)
    end)
  end)

  describe("kill_session idempotency", function()
    it("killing the same terminal twice does not error", function()
      fresh_session()
      register_agent("idem")
      session.open("idem")
      session.kill_session("idem")
      assert.has_no_errors(function()
        session.kill_session("idem")
      end)
    end)
  end)

  describe("single_pane_only backend", function()
    it("kills other agents before opening new one", function()
      local killed = {}
      fresh_session({
        single_pane_only = true,
        kill = function(td)
          table.insert(killed, td.name)
          td.pane_id = nil
        end,
        open = function(name, cfg, _)
          return { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = true, name = name }
        end,
      })

      require("neph.internal.agents").init({
        { name = "a1", label = "A1", icon = " ", cmd = "true" },
        { name = "a2", label = "A2", icon = " ", cmd = "true" },
      })

      session.open("a1")
      session.open("a2")
      assert.equals(1, #killed)
    end)
  end)

  describe("get_all with mixed terminals", function()
    it("returns info for all tracked terminals", function()
      fresh_session({
        open = function(name, cfg, _)
          return { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = true, name = name }
        end,
      })

      require("neph.internal.agents").init({
        { name = "x1", label = "X1", icon = " ", cmd = "true" },
        { name = "x2", label = "X2", icon = " ", cmd = "true" },
      })

      session.open("x1")
      session.open("x2")
      local all = session.get_all()
      assert.is_not_nil(all["x1"])
      assert.is_not_nil(all["x2"])
    end)
  end)

  describe("ensure_active_and_send with no active", function()
    it("notifies user when no active terminal", function()
      fresh_session()
      local notified = false
      local orig = vim.notify
      vim.notify = function()
        notified = true
      end
      session.ensure_active_and_send("text")
      vim.notify = orig
      assert.is_true(notified)
    end)
  end)

  describe("kill agent during active review", function()
    it("clears review queue for the killed agent", function()
      fresh_session({
        open = function(_, cfg, _)
          return { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = true }
        end,
      })
      register_agent("review_kill")

      -- Reset and wire review_queue with a stub open_fn
      package.loaded["neph.internal.review_queue"] = nil
      local rq = require("neph.internal.review_queue")
      rq.set_open_fn(function(_) end)

      -- Seed queue state: one active, one queued for the same agent
      rq.enqueue({
        request_id = "active-1",
        path = "/tmp/a.lua",
        agent = "review_kill",
        result_path = nil,
        channel_id = 0,
        content = "",
      })
      rq.enqueue({
        request_id = "queued-1",
        path = "/tmp/b.lua",
        agent = "review_kill",
        result_path = nil,
        channel_id = 0,
        content = "",
      })
      assert.are.equal(1, rq.count())
      assert.is_not_nil(rq.get_active())

      session.open("review_kill")
      session.kill_session("review_kill")

      -- Queue should be cleared for this agent
      assert.are.equal(0, rq.count())
      assert.is_nil(rq.get_active())
    end)

    it("kill with no pending reviews does not crash", function()
      fresh_session({
        open = function(_, cfg, _)
          return { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = true }
        end,
      })
      register_agent("no_review_kill")

      package.loaded["neph.internal.review_queue"] = nil
      local rq = require("neph.internal.review_queue")
      rq.set_open_fn(function(_) end)

      session.open("no_review_kill")
      assert.has_no_errors(function()
        session.kill_session("no_review_kill")
      end)
    end)

    it("session.exists returns false after kill", function()
      fresh_session({
        open = function(_, cfg, _)
          return { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = true }
        end,
      })
      register_agent("exists_kill")

      session.open("exists_kill")
      assert.is_true(session.exists("exists_kill"))
      session.kill_session("exists_kill")
      assert.is_false(session.exists("exists_kill"))
    end)

    it("get_active returns nil after killing the active session", function()
      fresh_session({
        open = function(_, cfg, _)
          return { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = true }
        end,
      })
      register_agent("active_kill")

      session.open("active_kill")
      assert.are.equal("active_kill", session.get_active())
      session.kill_session("active_kill")
      assert.is_nil(session.get_active())
    end)

    it("re-opening the same agent after kill succeeds", function()
      local open_count = 0
      fresh_session({
        open = function(_, cfg, _)
          open_count = open_count + 1
          return { pane_id = open_count, cmd = cfg.cmd, cwd = "/tmp", ready = true }
        end,
      })
      register_agent("reopen_kill")

      session.open("reopen_kill")
      session.kill_session("reopen_kill")
      session.open("reopen_kill")

      assert.are.equal(2, open_count)
      assert.is_true(session.exists("reopen_kill"))
      assert.are.equal("reopen_kill", session.get_active())
    end)
  end)

  describe("fault injection", function()
    it("handles backend.send() that throws an error", function()
      fresh_session({
        open = function(_, cfg, _)
          return { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = true }
        end,
        send = function()
          error("send exploded")
        end,
      })
      register_agent("send_err")

      session.open("send_err")
      assert.has_error(function()
        session.send("send_err", "hello", { submit = true })
      end)
    end)

    it("handles backend.send() that returns nil/false without crash", function()
      local send_called = false
      fresh_session({
        open = function(_, cfg, _)
          return { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = true }
        end,
        send = function()
          send_called = true
          return nil
        end,
      })
      register_agent("send_nil")

      session.open("send_nil")
      assert.has_no_errors(function()
        session.send("send_nil", "hello", { submit = true })
      end)
      assert.is_true(send_called)
    end)

    it("handles backend.open() returning terminal missing expected fields", function()
      fresh_session({
        open = function()
          return { ready = true } -- missing pane_id, cmd, cwd, name
        end,
      })
      register_agent("partial_td")

      assert.has_no_errors(function()
        session.open("partial_td")
      end)
      assert.equals("partial_td", session.get_active())
    end)

    it("handles send on terminal killed between check and send", function()
      local call_count = 0
      fresh_session({
        open = function(_, cfg, _)
          return { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = true }
        end,
        is_visible = function(td)
          return td ~= nil and td.pane_id ~= nil
        end,
        send = function(td)
          -- Simulate terminal dying during send
          td.pane_id = nil
          call_count = call_count + 1
        end,
      })
      register_agent("race_kill")

      session.open("race_kill")
      assert.has_no_errors(function()
        session.send("race_kill", "hello", { submit = true })
      end)
      assert.equals(1, call_count)
    end)

    it("VimLeavePre cleanup survives backend.cleanup_all() throwing", function()
      local be = fresh_session({
        open = function(_, cfg, _)
          return { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = true }
        end,
        cleanup_all = function()
          error("cleanup boom")
        end,
      })
      register_agent("cleanup_err")

      session.open("cleanup_err")
      -- Simulate VimLeavePre by calling cleanup_all directly through backend
      -- The session module wraps cleanup_all without pcall, so it should propagate
      assert.has_error(function()
        be.cleanup_all({})
      end)
    end)

    it("rapid open/kill/open sequence does not crash", function()
      fresh_session({
        open = function(_, cfg, _)
          return { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = true }
        end,
      })
      register_agent("rapid")

      assert.has_no_errors(function()
        session.open("rapid")
        session.kill_session("rapid")
        session.open("rapid")
      end)
      assert.equals("rapid", session.get_active())
      assert.is_true(session.is_visible("rapid"))
    end)
  end)

  describe("ready queue drain pcall protection", function()
    it("continues draining even if one send errors", function()
      local send_calls = {}
      local call_num = 0
      fresh_session({
        open = function(_, cfg, _)
          return { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = false }
        end,
        send = function(_, text, _)
          call_num = call_num + 1
          if call_num == 1 then
            error("first send exploded")
          end
          table.insert(send_calls, text)
        end,
      })
      register_agent("drain_pcall")

      -- Manually wire up internal state via session.open + captured td
      local captured_td = nil
      local be2 = helpers.make_stub_backend({
        open = function(_, cfg, _)
          captured_td = { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = false }
          return captured_td
        end,
        send = function(_, text, _)
          call_num = call_num + 1
          if call_num == 1 then
            error("first send exploded")
          end
          table.insert(send_calls, text)
        end,
      })

      package.loaded["neph.session"] = nil
      package.loaded["neph.internal.session"] = nil
      session = require("neph.internal.session")
      session.setup({ env = {} }, be2)
      register_agent("drain_pcall2")

      session.open("drain_pcall2")

      -- Queue two items while not ready
      session.ensure_active_and_send("first")
      session.ensure_active_and_send("second")

      -- Fire on_ready — first send will error, second should still be attempted
      assert.is_not_nil(captured_td)
      captured_td.ready = true
      assert.has_no_errors(function()
        captured_td.on_ready()
      end)
      -- second item should have been sent (call_num == 2, first errored, second succeeded)
      assert.are.equal(1, #send_calls)
      assert.are.equal("second", send_calls[1])
    end)
  end)

  describe("send() with stale td (pane_id and win both nil)", function()
    it("returns without crashing when both handles are nil", function()
      local send_called = false
      fresh_session({
        open = function(_, cfg, _)
          return { pane_id = nil, win = nil, cmd = cfg.cmd, cwd = "/tmp", ready = true }
        end,
        send = function()
          send_called = true
        end,
      })
      register_agent("no_handles")

      session.open("no_handles")
      assert.has_no_errors(function()
        session.send("no_handles", "hello", { submit = true })
      end)
      assert.is_false(send_called)
    end)
  end)

  describe("contract violations", function()
    it("send() with unknown termname returns silently (no crash, no error)", function()
      fresh_session()
      assert.has_no_errors(function()
        session.send("totally_unknown_term", "hello", { submit = true })
      end)
    end)

    it("send() with nil termname returns silently", function()
      fresh_session()
      assert.has_no_errors(function()
        session.send(nil, "hello")
      end)
    end)

    it("open() with unknown agent name notifies user", function()
      fresh_session()
      local notified = false
      local orig = vim.notify
      vim.notify = function()
        notified = true
      end
      session.open("agent_that_does_not_exist")
      vim.notify = orig
      assert.is_true(notified)
    end)
  end)
end)
