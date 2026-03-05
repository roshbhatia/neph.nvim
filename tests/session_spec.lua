---@diagnostic disable: undefined-global
-- session_spec.lua – unit tests for neph.session (no real terminals spawned)
--
-- We stub out the backend so nothing tries to launch actual processes.

local session

local function make_stub_backend(visible)
  return {
    setup = function() end,
    open = function(_, agent_cfg, _)
      return { pane_id = 999, cmd = agent_cfg.cmd, cwd = "/tmp", name = "stub" }
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
    session = require("neph.session")

    -- Stub the backend detection to always use our fake backend
    -- by monkey-patching the require inside setup
    local stub = make_stub_backend(true)
    -- Directly inject backend after setup
    session.setup({ env = {} })
    -- Override internal backend through a backdoor: call setup again with env
    -- We can't easily replace the backend after setup, so we'll test the public API only
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
end)
