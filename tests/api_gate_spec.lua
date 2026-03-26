---@diagnostic disable: undefined-global
-- api_gate_spec.lua – unit tests for neph.api gate() and gate_status()

local api, gate

describe("api gate functions", function()
  before_each(function()
    package.loaded["neph"] = nil
    package.loaded["neph.init"] = nil
    package.loaded["neph.internal.gate"] = nil
    package.loaded["neph.api"] = nil
    -- Stub heavy dependencies so api.lua loads in a minimal environment
    package.loaded["neph.internal.agents"] = {
      get_by_name = function()
        return nil
      end,
    }
    package.loaded["neph.internal.session"] = {
      get_active = function()
        return nil
      end,
      ensure_active_and_send = function() end,
    }
    gate = require("neph.internal.gate")
    api = require("neph.api")
  end)

  -- ---------------------------------------------------------------------------
  -- gate() – toggle behaviour
  -- ---------------------------------------------------------------------------

  describe("gate()", function()
    it("is exposed as a function", function()
      assert.is_function(api.gate)
    end)

    it("cycles normal → hold", function()
      assert.are.equal("normal", gate.get())
      api.gate()
      assert.are.equal("hold", gate.get())
    end)

    it("cycles hold → normal (release)", function()
      gate.set("hold")
      api.gate()
      assert.are.equal("normal", gate.get())
    end)

    it("cycles bypass → normal (release)", function()
      gate.set("bypass")
      api.gate()
      assert.are.equal("normal", gate.get())
    end)

    it("toggling twice from normal returns to normal", function()
      api.gate() -- → hold
      api.gate() -- → normal
      assert.are.equal("normal", gate.get())
    end)

    it("changes are reflected via gate module directly", function()
      api.gate()
      assert.is_true(gate.is_hold())
      api.gate()
      assert.is_true(gate.is_normal())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- gate_status()
  -- ---------------------------------------------------------------------------

  describe("gate_status()", function()
    it("is exposed as a function", function()
      assert.is_function(api.gate_status)
    end)

    it("returns 'normal' initially", function()
      assert.are.equal("normal", api.gate_status())
    end)

    it("returns 'hold' after gate.set('hold')", function()
      gate.set("hold")
      assert.are.equal("hold", api.gate_status())
    end)

    it("returns 'bypass' after gate.set('bypass')", function()
      gate.set("bypass")
      assert.are.equal("bypass", api.gate_status())
    end)

    it("reflects state changed via api.gate()", function()
      api.gate() -- → hold
      assert.are.equal("hold", api.gate_status())
    end)

    it("tracks release back to normal", function()
      gate.set("hold")
      gate.release()
      assert.are.equal("normal", api.gate_status())
    end)
  end)
end)
