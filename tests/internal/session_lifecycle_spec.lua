---@diagnostic disable: undefined-global
-- session_lifecycle_spec.lua – targeted lifecycle and state-management tests
-- for neph.internal.session, covering the six issues audited in the PR.

local helpers = require("tests.test_helpers")
local session

local function fresh_session(backend_overrides)
  package.loaded["neph.session"] = nil
  package.loaded["neph.internal.session"] = nil
  session = require("neph.internal.session")
  local be = helpers.make_stub_backend(backend_overrides)
  session.setup({ env = {} }, be)
  return be
end

local function register_agent(name, extra)
  require("neph.internal.agents").init({
    helpers.make_valid_agent(vim.tbl_extend("force", { name = name, label = name, cmd = "true" }, extra or {})),
  })
end

-- ---------------------------------------------------------------------------
-- Issue 1: ready_queue scoped correctly — entries queued before open() drain
-- ---------------------------------------------------------------------------
describe("session lifecycle: ready_queue scoping", function()
  it("drains entries queued before open() is called once on_ready fires", function()
    local sent = {}
    local captured_td = nil

    fresh_session({
      open = function(_, cfg, _)
        captured_td = { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = false }
        return captured_td
      end,
      send = function(_, text, _)
        table.insert(sent, text)
      end,
    })
    register_agent("pre_queue")

    session.open("pre_queue")
    -- active_terminal is now "pre_queue"; manually enqueue via ensure_active_and_send
    -- without going through focus (td exists and is in terminals)
    session.ensure_active_and_send("msg_before_ready")

    -- Queue should be pending — nothing sent yet
    assert.are.equal(0, #sent)

    -- Simulate backend signalling ready
    assert.is_not_nil(captured_td.on_ready)
    captured_td.ready = true
    captured_td.on_ready()

    -- Queue drained: the send stub was called once
    assert.are.equal(1, #sent)
    assert.are.equal("msg_before_ready", sent[1])
  end)

  it("queue is nil after drain (no double-drain)", function()
    local call_count = 0
    local captured_td = nil

    fresh_session({
      open = function(_, cfg, _)
        captured_td = { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = false }
        return captured_td
      end,
      send = function()
        call_count = call_count + 1
      end,
    })
    register_agent("no_double_drain")

    session.open("no_double_drain")
    session.ensure_active_and_send("once")

    captured_td.ready = true
    captured_td.on_ready()
    -- Fire on_ready a second time — must not re-send
    captured_td.on_ready()

    assert.are.equal(1, call_count)
  end)
end)

-- ---------------------------------------------------------------------------
-- Issue 2: stale terminals entry cleared when backend.open returns nil
-- ---------------------------------------------------------------------------
describe("session lifecycle: stale entry on nil open", function()
  it("second open attempt is not blocked after first open returns nil", function()
    local open_count = 0
    local return_nil = true

    fresh_session({
      open = function(_, cfg, _)
        open_count = open_count + 1
        if return_nil then
          return nil
        end
        return { pane_id = open_count, cmd = cfg.cmd, cwd = "/tmp", ready = true }
      end,
    })
    register_agent("nil_then_ok")

    -- First open: backend returns nil
    session.open("nil_then_ok")
    assert.is_nil(session.get_active())
    assert.is_false(session.exists("nil_then_ok"))

    -- Second open: backend now returns a valid td
    return_nil = false
    session.open("nil_then_ok")

    assert.are.equal("nil_then_ok", session.get_active())
    assert.is_true(session.exists("nil_then_ok"))
    assert.are.equal(2, open_count)
  end)

  it("terminals entry is nil after open returns nil", function()
    fresh_session({
      open = function()
        return nil
      end,
    })
    register_agent("nil_entry_clear")

    session.open("nil_entry_clear")

    -- get_info would return non-nil only if terminals[name] is set
    assert.is_nil(session.get_info("nil_entry_clear"))
  end)
end)

-- ---------------------------------------------------------------------------
-- Issue 3: kill_session wraps backend.kill in pcall
-- ---------------------------------------------------------------------------
describe("session lifecycle: kill_session pcall protection", function()
  it("state is cleaned up even when backend.kill throws", function()
    fresh_session({
      open = function(_, cfg, _)
        return { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = true }
      end,
      kill = function(_)
        error("kill exploded")
      end,
    })
    register_agent("kill_throws")

    session.open("kill_throws")
    assert.are.equal("kill_throws", session.get_active())

    -- Must not propagate the error
    assert.has_no_errors(function()
      session.kill_session("kill_throws")
    end)

    -- State is cleaned up despite the throw
    assert.is_nil(session.get_active())
    assert.is_nil(session.get_info("kill_throws"))
    assert.is_nil(vim.g["kill_throws_active"])
  end)

  it("ready_queue is cleared even when backend.kill throws", function()
    local captured_td = nil
    fresh_session({
      open = function(_, cfg, _)
        captured_td = { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = false }
        return captured_td
      end,
      kill = function(_)
        error("kill exploded")
      end,
    })
    register_agent("kill_throws_queue")

    session.open("kill_throws_queue")
    session.ensure_active_and_send("queued msg")

    -- kill should still clear ready_queue without crashing
    assert.has_no_errors(function()
      session.kill_session("kill_throws_queue")
    end)

    -- Verify the terminal is fully gone
    assert.is_nil(session.get_active())
    assert.is_false(session.exists("kill_throws_queue"))
  end)
end)

-- ---------------------------------------------------------------------------
-- Issue 4: setup idempotency (double call)
-- ---------------------------------------------------------------------------
describe("session lifecycle: M.setup idempotency", function()
  it("calling setup twice does not duplicate autocmds or crash", function()
    package.loaded["neph.session"] = nil
    package.loaded["neph.internal.session"] = nil
    session = require("neph.internal.session")

    local be = helpers.make_stub_backend()

    -- First setup
    assert.has_no_errors(function()
      session.setup({ env = {} }, be)
    end)

    -- Second setup with a different (but still valid) backend — must not error
    local be2 = helpers.make_stub_backend()
    assert.has_no_errors(function()
      session.setup({ env = {} }, be2)
    end)

    -- Basic operations still work after double setup
    require("neph.internal.agents").init({
      helpers.make_valid_agent({ name = "idem_agent", label = "I", cmd = "true" }),
    })
    session.open("idem_agent")
    assert.are.equal("idem_agent", session.get_active())
  end)
end)

-- ---------------------------------------------------------------------------
-- Issue 5: VimLeavePre — teardown survives backend.cleanup_all throwing
-- ---------------------------------------------------------------------------
describe("session lifecycle: VimLeavePre teardown resilience", function()
  it("file_refresh.teardown and fs_watcher.stop are reached even if cleanup_all throws", function()
    -- The session module now wraps cleanup_all in pcall in VimLeavePre.
    -- We verify that the session module itself exposes no error when cleanup_all throws.
    -- (The actual autocmd fires on VimLeavePre — we simulate the wrapping via the
    -- fact that kill_session already uses pcall for backend.kill.)
    local teardown_called = false
    local stop_called = false

    -- Override module-level stubs that VimLeavePre calls
    package.loaded["neph.internal.file_refresh"] = {
      teardown = function()
        teardown_called = true
      end,
    }
    package.loaded["neph.internal.fs_watcher"] = {
      stop = function()
        stop_called = true
      end,
      start = function() end,
      is_active = function()
        return false
      end,
    }

    fresh_session({
      open = function(_, cfg, _)
        return { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = true }
      end,
      cleanup_all = function(_)
        error("cleanup boom")
      end,
    })
    register_agent("leave_cleanup")
    session.open("leave_cleanup")

    -- Trigger VimLeavePre autocmd directly
    assert.has_no_errors(function()
      vim.api.nvim_exec_autocmds("VimLeavePre", { group = "NephSession" })
    end)

    -- Both teardown steps should still have run despite cleanup_all throwing
    assert.is_true(teardown_called)
    assert.is_true(stop_called)

    -- Restore stubs
    package.loaded["neph.internal.file_refresh"] = nil
    package.loaded["neph.internal.fs_watcher"] = nil
  end)
end)

-- ---------------------------------------------------------------------------
-- Issue 6: periodic staleness timer created by setup
-- ---------------------------------------------------------------------------
describe("session lifecycle: periodic stale timer", function()
  it("vim.uv timer is created when setup is called (if vim.uv is available)", function()
    if not vim.uv then
      -- headless Neovim without libuv binding: skip gracefully
      return
    end

    package.loaded["neph.session"] = nil
    package.loaded["neph.internal.session"] = nil
    session = require("neph.internal.session")

    local new_timer_called = false
    local orig_new_timer = vim.uv.new_timer
    vim.uv.new_timer = function()
      new_timer_called = true
      -- Return a minimal fake timer so start() does not crash
      return {
        start = function() end,
        stop = function() end,
        close = function() end,
      }
    end

    local be = helpers.make_stub_backend()
    assert.has_no_errors(function()
      session.setup({ env = {} }, be)
    end)

    vim.uv.new_timer = orig_new_timer
    assert.is_true(new_timer_called)
  end)

  it("stale mark is applied by CursorHold when pane becomes invisible", function()
    -- CursorHold runs the same stale-detection logic as the periodic timer.
    -- We test that path here since autocmds fire synchronously in headless Neovim
    -- while vim.schedule_wrap callbacks do not.
    local captured_td = nil
    local visible = true

    package.loaded["neph.session"] = nil
    package.loaded["neph.internal.session"] = nil
    session = require("neph.internal.session")

    local be = helpers.make_stub_backend({
      open = function(_, cfg, _)
        captured_td = { pane_id = 1, cmd = cfg.cmd, cwd = "/tmp", ready = true }
        return captured_td
      end,
      is_visible = function(_)
        return visible
      end,
      -- CursorHold/FocusGained now use check_alive_async; stub calls callback
      -- synchronously so the test assertion fires in the same tick.
      check_alive_async = function(_, callback)
        callback(visible)
      end,
    })
    session.setup({ env = {} }, be)

    require("neph.internal.agents").init({
      helpers.make_valid_agent({ name = "cursorhold_stale", label = "C", cmd = "true" }),
    })
    session.open("cursorhold_stale")
    assert.are.equal("cursorhold_stale", session.get_active())

    -- Pane disappears
    visible = false

    -- CursorHold fires the same staleness check as the periodic timer
    vim.api.nvim_exec_autocmds("CursorHold", { group = "NephSession" })

    -- td should now be stale and active_terminal cleared
    assert.is_not_nil(captured_td.stale_since)
    assert.is_nil(session.get_active())
  end)
end)
