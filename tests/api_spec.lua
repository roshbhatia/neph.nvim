---@diagnostic disable: undefined-global
-- api_spec.lua -- unit tests for neph.api public functions

describe("neph.api", function()
  local api
  local mock_session, mock_picker, mock_agents, mock_input

  before_each(function()
    -- Create mocks
    mock_session = {
      get_active = function()
        return nil
      end,
      ensure_active_and_send = function() end,
    }
    mock_picker = {
      pick_agent = function() end,
      kill_and_pick = function() end,
      kill_active = function() end,
    }
    mock_agents = {
      get_by_name = function(name)
        if name == "claude" then
          return { name = "claude", icon = " ", label = "Claude" }
        end
        return nil
      end,
    }
    mock_input = {
      create_input = function() end,
    }

    -- Inject mocks
    package.loaded["neph.internal.session"] = mock_session
    package.loaded["neph.internal.picker"] = mock_picker
    package.loaded["neph.internal.agents"] = mock_agents
    package.loaded["neph.internal.input"] = mock_input

    -- Reload api
    package.loaded["neph.api"] = nil
    api = require("neph.api")
  end)

  after_each(function()
    package.loaded["neph.internal.session"] = nil
    package.loaded["neph.internal.picker"] = nil
    package.loaded["neph.internal.agents"] = nil
    package.loaded["neph.internal.input"] = nil
    package.loaded["neph.api"] = nil
  end)

  describe("toggle()", function()
    it("delegates to picker.pick_agent", function()
      local called = false
      mock_picker.pick_agent = function()
        called = true
      end
      api.toggle()
      assert.is_true(called)
    end)
  end)

  describe("kill_and_pick()", function()
    it("delegates to picker.kill_and_pick", function()
      local called = false
      mock_picker.kill_and_pick = function()
        called = true
      end
      api.kill_and_pick()
      assert.is_true(called)
    end)
  end)

  describe("kill()", function()
    it("delegates to picker.kill_active", function()
      local called = false
      mock_picker.kill_active = function()
        called = true
      end
      api.kill()
      assert.is_true(called)
    end)
  end)

  describe("ask()", function()
    it("does nothing when no active session", function()
      local input_called = false
      mock_input.create_input = function()
        input_called = true
      end
      api.ask()
      assert.is_false(input_called)
    end)

    it("opens input when active session exists", function()
      mock_session.get_active = function()
        return "claude"
      end
      local captured_action, captured_default
      mock_input.create_input = function(_, _, opts)
        captured_action = opts.action
        captured_default = opts.default
      end
      api.ask()
      assert.are.equal("Ask", captured_action)
      assert.is_string(captured_default)
    end)

    it("does nothing when agent not found", function()
      mock_session.get_active = function()
        return "unknown_agent"
      end
      local input_called = false
      mock_input.create_input = function()
        input_called = true
      end
      api.ask()
      assert.is_false(input_called)
    end)
  end)

  describe("fix()", function()
    it("opens input with fix action when active", function()
      mock_session.get_active = function()
        return "claude"
      end
      local captured_action, captured_default
      mock_input.create_input = function(_, _, opts)
        captured_action = opts.action
        captured_default = opts.default
      end
      api.fix()
      assert.are.equal("Fix diagnostics", captured_action)
      assert.are.equal("Fix +diagnostics ", captured_default)
    end)
  end)

  describe("comment()", function()
    it("opens input with comment action when active", function()
      mock_session.get_active = function()
        return "claude"
      end
      local captured_action
      mock_input.create_input = function(_, _, opts)
        captured_action = opts.action
      end
      api.comment()
      assert.are.equal("Comment", captured_action)
    end)
  end)

  describe("resend()", function()
    it("does nothing when no active session", function()
      local send_called = false
      mock_session.ensure_active_and_send = function()
        send_called = true
      end
      api.resend()
      assert.is_false(send_called)
    end)

    it("sends last prompt when available", function()
      mock_session.get_active = function()
        return "claude"
      end
      package.loaded["neph.internal.terminal"] = {
        get_last_prompt = function()
          return "hello world"
        end,
      }
      local sent_text
      mock_session.ensure_active_and_send = function(text)
        sent_text = text
      end
      api.resend()
      assert.are.equal("hello world", sent_text)
      package.loaded["neph.internal.terminal"] = nil
    end)

    it("notifies when no previous prompt", function()
      mock_session.get_active = function()
        return "claude"
      end
      package.loaded["neph.internal.terminal"] = {
        get_last_prompt = function()
          return nil
        end,
      }
      -- Should not error
      assert.has_no.errors(function()
        api.resend()
      end)
      package.loaded["neph.internal.terminal"] = nil
    end)
  end)
end)
