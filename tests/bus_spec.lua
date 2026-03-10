local bus = require("neph.internal.bus")

describe("neph.internal.bus", function()
  before_each(function()
    bus._reset()
    -- Ensure the agents module knows about a test extension agent
    local agents = require("neph.internal.agents")
    agents.init({
      { name = "pi", label = "Pi", icon = "", cmd = "echo", type = "extension" },
      { name = "goose", label = "Goose", icon = "", cmd = "echo" },
    })
  end)

  after_each(function()
    bus._reset()
    vim.g.pi_active = nil
  end)

  describe("register", function()
    it("registers a known extension agent", function()
      local result = bus.register({ name = "pi", channel = 5 })
      assert.is_true(result.ok)
      assert.is_true(bus.is_connected("pi"))
      -- vim.g.pi_active is managed by session.lua, not bus.lua
    end)

    it("rejects unknown agent", function()
      local result = bus.register({ name = "unknown", channel = 5 })
      assert.is_false(result.ok)
      assert.truthy(result.error:find("unknown"))
    end)

    it("rejects non-extension agent", function()
      local result = bus.register({ name = "goose", channel = 5 })
      assert.is_false(result.ok)
    end)

    it("updates channel on re-register", function()
      bus.register({ name = "pi", channel = 5 })
      bus.register({ name = "pi", channel = 9 })
      assert.are.equal(9, bus._get_channels()["pi"])
    end)

    it("rejects missing name", function()
      local result = bus.register({ channel = 5 })
      assert.is_false(result.ok)
    end)

    it("rejects missing channel", function()
      local result = bus.register({ name = "pi" })
      assert.is_false(result.ok)
    end)
  end)

  describe("send_prompt", function()
    it("returns false for unconnected agent", function()
      assert.is_false(bus.send_prompt("pi", "hello", { submit = true }))
    end)

    it("returns false for unknown agent", function()
      assert.is_false(bus.send_prompt("nonexistent", "hello", {}))
    end)
  end)

  describe("is_connected", function()
    it("returns false when not registered", function()
      assert.is_false(bus.is_connected("pi"))
    end)

    it("returns true when registered", function()
      bus.register({ name = "pi", channel = 5 })
      assert.is_true(bus.is_connected("pi"))
    end)
  end)

  describe("unregister", function()
    it("removes agent from bus", function()
      bus.register({ name = "pi", channel = 5 })
      bus.unregister("pi")
      assert.is_false(bus.is_connected("pi"))
      -- vim.g.pi_active is managed by session.lua, not bus.lua
    end)

    it("is no-op for unregistered agent", function()
      assert.has_no.errors(function()
        bus.unregister("pi")
      end)
    end)
  end)

  describe("cleanup_all", function()
    it("clears all channels", function()
      bus.register({ name = "pi", channel = 5 })
      bus.cleanup_all()
      assert.is_false(bus.is_connected("pi"))
      -- vim.g.pi_active is managed by session.lua, not bus.lua
    end)
  end)
end)
