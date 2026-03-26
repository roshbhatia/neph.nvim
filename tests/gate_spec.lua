---@diagnostic disable: undefined-global
-- gate_spec.lua – unit tests for neph.internal.gate

local gate

describe("neph.internal.gate", function()
  before_each(function()
    package.loaded["neph.internal.gate"] = nil
    gate = require("neph.internal.gate")
  end)

  -- ---------------------------------------------------------------------------
  -- Initial state
  -- ---------------------------------------------------------------------------

  it("initial state is normal", function()
    assert.are.equal("normal", gate.get())
  end)

  -- ---------------------------------------------------------------------------
  -- set() transitions
  -- ---------------------------------------------------------------------------

  describe("set()", function()
    it("transitions to hold", function()
      gate.set("hold")
      assert.are.equal("hold", gate.get())
    end)

    it("transitions to bypass", function()
      gate.set("bypass")
      assert.are.equal("bypass", gate.get())
    end)

    it("transitions back to normal", function()
      gate.set("hold")
      gate.set("normal")
      assert.are.equal("normal", gate.get())
    end)

    it("errors on invalid state", function()
      assert.has_error(function()
        gate.set("invalid")
      end)
    end)

    it("errors on empty string", function()
      assert.has_error(function()
        gate.set("")
      end)
    end)

    it("errors on nil", function()
      assert.has_error(function()
        gate.set(nil)
      end)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- release()
  -- ---------------------------------------------------------------------------

  describe("release()", function()
    it("sets state to normal from hold", function()
      gate.set("hold")
      gate.release()
      assert.are.equal("normal", gate.get())
    end)

    it("sets state to normal from bypass", function()
      gate.set("bypass")
      gate.release()
      assert.are.equal("normal", gate.get())
    end)

    it("is idempotent when already normal", function()
      gate.release()
      assert.are.equal("normal", gate.get())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Predicate helpers
  -- ---------------------------------------------------------------------------

  describe("is_hold()", function()
    it("returns true when state is hold", function()
      gate.set("hold")
      assert.is_true(gate.is_hold())
    end)

    it("returns false when state is normal", function()
      assert.is_false(gate.is_hold())
    end)

    it("returns false when state is bypass", function()
      gate.set("bypass")
      assert.is_false(gate.is_hold())
    end)
  end)

  describe("is_bypass()", function()
    it("returns true when state is bypass", function()
      gate.set("bypass")
      assert.is_true(gate.is_bypass())
    end)

    it("returns false when state is normal", function()
      assert.is_false(gate.is_bypass())
    end)

    it("returns false when state is hold", function()
      gate.set("hold")
      assert.is_false(gate.is_bypass())
    end)
  end)

  describe("is_normal()", function()
    it("returns true when state is normal", function()
      assert.is_true(gate.is_normal())
    end)

    it("returns false when state is hold", function()
      gate.set("hold")
      assert.is_false(gate.is_normal())
    end)

    it("returns false when state is bypass", function()
      gate.set("bypass")
      assert.is_false(gate.is_normal())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- cycle()
  -- ---------------------------------------------------------------------------

  describe("cycle()", function()
    it("advances normal → hold", function()
      gate.cycle()
      assert.are.equal("hold", gate.get())
    end)

    it("advances hold → bypass", function()
      gate.set("hold")
      gate.cycle()
      assert.are.equal("bypass", gate.get())
    end)

    it("advances bypass → normal", function()
      gate.set("bypass")
      gate.cycle()
      assert.are.equal("normal", gate.get())
    end)

    it("full cycle returns to normal", function()
      gate.cycle() -- → hold
      gate.cycle() -- → bypass
      gate.cycle() -- → normal
      assert.are.equal("normal", gate.get())
    end)
  end)
end)
