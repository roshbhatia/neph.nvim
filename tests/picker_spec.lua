---@diagnostic disable: undefined-global
-- picker_spec.lua -- tests for neph.internal.picker

describe("neph.internal.picker", function()
  local picker
  local mock_session, mock_agents

  before_each(function()
    mock_session = {
      get_active = function()
        return nil
      end,
      is_tracked = function()
        return false
      end,
      is_visible = function()
        return false
      end,
      hide = function() end,
      activate = function() end,
      kill_session = function() end,
    }
    mock_agents = {
      get_all = function()
        return {
          { name = "claude", icon = " ", label = "Claude" },
          { name = "copilot", icon = " ", label = "Copilot" },
        }
      end,
    }

    package.loaded["neph.internal.session"] = mock_session
    package.loaded["neph.internal.agents"] = mock_agents
    package.loaded["neph.internal.picker"] = nil
    picker = require("neph.internal.picker")
  end)

  after_each(function()
    package.loaded["neph.internal.session"] = nil
    package.loaded["neph.internal.agents"] = nil
    package.loaded["neph.internal.picker"] = nil
  end)

  describe("pick_agent()", function()
    it("hides visible active session", function()
      local hidden = false
      mock_session.get_active = function()
        return "claude"
      end
      mock_session.is_tracked = function()
        return true
      end
      mock_session.is_visible = function()
        return true
      end
      mock_session.hide = function()
        hidden = true
      end
      picker.pick_agent()
      assert.is_true(hidden)
    end)

    it("activates hidden active session", function()
      local activated = false
      mock_session.get_active = function()
        return "claude"
      end
      mock_session.is_tracked = function()
        return true
      end
      mock_session.is_visible = function()
        return false
      end
      mock_session.activate = function()
        activated = true
      end
      picker.pick_agent()
      assert.is_true(activated)
    end)

    it("opens picker when no active session", function()
      local select_called = false
      local orig = vim.ui.select
      vim.ui.select = function(items, _opts, cb)
        select_called = true
        assert.are.equal(2, #items)
        cb(items[1])
      end
      local activated_name
      mock_session.activate = function(name)
        activated_name = name
      end
      picker.pick_agent()
      assert.is_true(select_called)
      assert.are.equal("claude", activated_name)
      vim.ui.select = orig
    end)

    it("does nothing when picker cancelled", function()
      local activated = false
      local orig = vim.ui.select
      vim.ui.select = function(_, _, cb)
        cb(nil)
      end
      mock_session.activate = function()
        activated = true
      end
      picker.pick_agent()
      assert.is_false(activated)
      vim.ui.select = orig
    end)

    it("notifies when no agents available", function()
      mock_agents.get_all = function()
        return {}
      end
      assert.has_no.errors(function()
        picker.pick_agent()
      end)
    end)
  end)

  describe("kill_and_pick()", function()
    it("kills active session then opens picker", function()
      local killed = false
      mock_session.get_active = function()
        return "claude"
      end
      mock_session.kill_session = function()
        killed = true
      end
      -- After kill, get_active returns nil for the picker path
      local call_count = 0
      mock_session.get_active = function()
        call_count = call_count + 1
        if call_count == 1 then
          return "claude"
        end
        return nil
      end
      local orig = vim.ui.select
      vim.ui.select = function(_, _, cb)
        cb(nil)
      end
      picker.kill_and_pick()
      assert.is_true(killed)
      vim.ui.select = orig
    end)
  end)

  describe("kill_active()", function()
    it("kills the active session", function()
      local killed_name
      mock_session.get_active = function()
        return "claude"
      end
      mock_session.kill_session = function(name)
        killed_name = name
      end
      picker.kill_active()
      assert.are.equal("claude", killed_name)
    end)

    it("does nothing when no active session", function()
      local killed = false
      mock_session.kill_session = function()
        killed = true
      end
      picker.kill_active()
      assert.is_false(killed)
    end)
  end)
end)
