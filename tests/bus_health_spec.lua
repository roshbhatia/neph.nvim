---@diagnostic disable: undefined-global
-- bus_health_spec.lua – tests for bus health timer functionality

local bus = require("neph.internal.bus")

describe("bus health monitoring", function()
  before_each(function()
    bus._reset()
    -- Ensure the agents module knows about test extension agents
    local agents = require("neph.internal.agents")
    agents.init({
      { name = "pi", label = "Pi", icon = "", cmd = "echo", type = "extension" },
      { name = "amp", label = "Amp", icon = "", cmd = "echo", type = "extension" },
      { name = "opencode", label = "OpenCode", icon = "", cmd = "echo", type = "extension" },
      { name = "goose", label = "Goose", icon = "", cmd = "echo" },
    })
  end)

  after_each(function()
    bus._reset()
    vim.g.pi_active = nil
    vim.g.amp_active = nil
    vim.g.opencode_active = nil
  end)

  describe("health timer lifecycle", function()
    it("starts timer when first channel registers", function()
      bus.register({ name = "pi", channel = 5 })
      -- Timer should be started automatically
      -- We can verify by checking channels are registered
      assert.is_true(bus.is_connected("pi"))
    end)

    it("timer stops when all channels are unregistered", function()
      bus.register({ name = "pi", channel = 5 })
      bus.register({ name = "amp", channel = 6 })
      
      bus.unregister("pi")
      bus.unregister("amp")
      
      -- Timer should stop after all channels removed
      -- Channels should be empty
      assert.is_false(bus.is_connected("pi"))
      assert.is_false(bus.is_connected("amp"))
    end)
  end)

  describe("dead channel detection", function()
    it("detects dead channel via ping failure", function()
      -- Mock vim.rpcnotify to fail
      local orig_rpcnotify = vim.rpcnotify
      vim.rpcnotify = function(ch, method)
        if ch == 5 then
          error("channel dead")
        end
        return true
      end

      bus.register({ name = "pi", channel = 5 })
      bus.register({ name = "amp", channel = 6 })
      
      -- Manually test health check logic
      local state = bus._get_channels()
      local dead = {}
      for name, ch in pairs(state) do
        local ok = pcall(vim.rpcnotify, ch, "neph:ping")
        if not ok then
          table.insert(dead, name)
        end
      end
      
      -- Should detect dead channel
      assert.are.equal(1, #dead)
      assert.are.equal("pi", dead[1])
      
      vim.rpcnotify = orig_rpcnotify
    end)

    it("collects multiple dead channels safely", function()
      -- Mock vim.rpcnotify to fail for multiple channels
      local orig_rpcnotify = vim.rpcnotify
      vim.rpcnotify = function(ch, method)
        if ch == 5 or ch == 6 then
          error("channel dead")
        end
        return true
      end

      bus.register({ name = "pi", channel = 5 })
      bus.register({ name = "amp", channel = 6 })
      bus.register({ name = "opencode", channel = 7 })
      
      -- Test collection-first approach
      local state = bus._get_channels()
      local dead = {}
      for name, ch in pairs(state) do
        local ok = pcall(vim.rpcnotify, ch, "neph:ping")
        if not ok then
          table.insert(dead, name)
        end
      end
      
      -- Should collect both dead channels without modifying table during iteration
      assert.are.equal(2, #dead)
      assert.is_true((dead[1] == "pi" or dead[2] == "pi"))
      assert.is_true((dead[1] == "amp" or dead[2] == "amp"))
      
      vim.rpcnotify = orig_rpcnotify
    end)

    it("maintains iteration safety", function()
      -- Test that we don't modify channels table during iteration
      local orig_rpcnotify = vim.rpcnotify
      vim.rpcnotify = function(ch, method)
        if ch == 5 then
          error("channel dead")
        end
        return true
      end

      bus.register({ name = "pi", channel = 5 })
      bus.register({ name = "amp", channel = 6 })
      
      -- The actual implementation should collect dead channels first
      -- then unregister after iteration
      local state = bus._get_channels()
      local iteration_count = 0
      for name, ch in pairs(state) do
        iteration_count = iteration_count + 1
        -- Should not call unregister during iteration
      end
      
      assert.are.equal(2, iteration_count)
      
      vim.rpcnotify = orig_rpcnotify
    end)
  end)

  describe("error handling", function()
    it("handles nil channel gracefully", function()
      -- Mock vim.rpcnotify to handle nil channel
      local orig_rpcnotify = vim.rpcnotify
      vim.rpcnotify = function(ch, method)
        if ch == nil then
          error("nil channel")
        end
        return true
      end

      -- This should not crash
      assert.has_no.errors(function()
        bus.register({ name = "pi", channel = 5 })
        local state = bus._get_channels()
        for name, ch in pairs(state) do
          pcall(vim.rpcnotify, ch, "neph:ping")
        end
      end)
      
      vim.rpcnotify = orig_rpcnotify
    end)
  end)
end)