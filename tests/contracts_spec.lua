local contracts = require("neph.internal.contracts")

describe("neph.contracts", function()
  describe("validate_agent", function()
    it("accepts a valid agent with required fields only", function()
      assert.has_no.errors(function()
        contracts.validate_agent({ name = "test", label = "Test", icon = " ", cmd = "test" })
      end)
    end)

    it("accepts a valid agent with all optional fields", function()
      assert.has_no.errors(function()
        contracts.validate_agent({
          name = "pi",
          label = "Pi",
          icon = " ",
          cmd = "pi",
          args = { "--continue" },
          send_adapter = function() end,
          integration = { type = "extension", capabilities = { "review" } },
        })
      end)
    end)

    it("throws on missing required field 'cmd'", function()
      assert.has_error(function()
        contracts.validate_agent({ name = "test", label = "Test", icon = " " })
      end, "neph: agent 'test' missing required field 'cmd'")
    end)

    it("throws on missing required field 'name'", function()
      assert.has_error(function()
        contracts.validate_agent({ label = "Test", icon = " ", cmd = "test" })
      end)
    end)

    it("throws on wrong type for required field", function()
      assert.has_error(function()
        contracts.validate_agent({ name = "test", label = "Test", icon = " ", cmd = 42 })
      end, "neph: agent 'test' field 'cmd' must be string, got number")
    end)

    it("throws on wrong type for optional field 'args'", function()
      assert.has_error(function()
        contracts.validate_agent({ name = "test", label = "Test", icon = " ", cmd = "test", args = "bad" })
      end, "neph: agent 'test' field 'args' must be table, got string")
    end)

    it("throws on wrong type for optional field 'send_adapter'", function()
      assert.has_error(function()
        contracts.validate_agent({ name = "test", label = "Test", icon = " ", cmd = "test", send_adapter = "bad" })
      end, "neph: agent 'test' field 'send_adapter' must be function, got string")
    end)

    it("ignores unknown fields", function()
      assert.has_no.errors(function()
        contracts.validate_agent({ name = "test", label = "Test", icon = " ", cmd = "test", custom_field = true })
      end)
    end)
  end)

  describe("validate_backend", function()
    local function make_valid_backend()
      return {
        setup = function() end,
        open = function() end,
        focus = function() end,
        hide = function() end,
        is_visible = function() end,
        kill = function() end,
        cleanup_all = function() end,
      }
    end

    it("accepts a valid backend", function()
      assert.has_no.errors(function()
        contracts.validate_backend(make_valid_backend(), "snacks")
      end)
    end)

    it("throws on missing required method", function()
      local mod = make_valid_backend()
      mod.focus = nil
      assert.has_error(function()
        contracts.validate_backend(mod, "snacks")
      end, "neph: backend 'snacks' missing required method 'focus'")
    end)

    it("throws when method is not a function", function()
      local mod = make_valid_backend()
      mod.kill = "not a function"
      assert.has_error(function()
        contracts.validate_backend(mod, "test")
      end, "neph: backend 'test' missing required method 'kill'")
    end)

    it("accepts backend with extra methods", function()
      local mod = make_valid_backend()
      mod.show = function() end
      assert.has_no.errors(function()
        contracts.validate_backend(mod, "snacks")
      end)
    end)
  end)
end)
