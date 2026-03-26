---@diagnostic disable: undefined-global
-- session_boundary_spec.lua -- boundary/adversarial tests for neph.session

local session

local function register_agent(name, extra)
  local def = vim.tbl_extend("force", {
    name = name,
    label = name,
    icon = " ",
    cmd = "true",
  }, extra or {})
  require("neph.internal.agents").init({ def })
end

local function make_backend(overrides)
  local base = {
    setup = function() end,
    open = function(_, agent_cfg, _)
      return { pane_id = 1, cmd = agent_cfg.cmd, cwd = "/tmp", ready = true }
    end,
    focus = function()
      return true
    end,
    hide = function(td)
      td.pane_id = nil
    end,
    is_visible = function(td)
      return td ~= nil and td.pane_id ~= nil
    end,
    kill = function(td)
      td.pane_id = nil
    end,
    cleanup_all = function() end,
  }
  return vim.tbl_extend("force", base, overrides or {})
end

local function fresh_session(backend_overrides)
  package.loaded["neph.session"] = nil
  package.loaded["neph.internal.session"] = nil
  session = require("neph.internal.session")
  local be = make_backend(backend_overrides)
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
end)
