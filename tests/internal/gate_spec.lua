---@diagnostic disable: undefined-global
-- tests/internal/gate_spec.lua
-- Comprehensive tests for neph.internal.gate and neph.internal.gate_ui

local gate
local gate_ui

local function fresh_gate()
  package.loaded["neph.internal.gate"] = nil
  return require("neph.internal.gate")
end

-- ---------------------------------------------------------------------------
-- neph.internal.gate
-- ---------------------------------------------------------------------------

describe("neph.internal.gate", function()
  before_each(function()
    gate = fresh_gate()
  end)

  -- Initial state

  it("initial state is bypass (open-by-default)", function()
    assert.are.equal("bypass", gate.get())
  end)

  -- set() transitions

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

    it("is idempotent for the same state", function()
      gate.set("hold")
      gate.set("hold")
      assert.are.equal("hold", gate.get())
    end)

    it("errors on invalid state string", function()
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

    it("errors on number", function()
      assert.has_error(function()
        gate.set(42)
      end)
    end)
  end)

  -- release()

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

  -- Predicate helpers

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
      gate.set("normal")
      assert.is_false(gate.is_bypass())
    end)

    it("returns false when state is hold", function()
      gate.set("hold")
      assert.is_false(gate.is_bypass())
    end)
  end)

  describe("is_normal()", function()
    it("returns true when state is normal", function()
      gate.set("normal")
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

  -- cycle()

  describe("cycle()", function()
    it("advances normal → hold", function()
      gate.set("normal")
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
      gate.set("normal")
      gate.cycle() -- → hold
      gate.cycle() -- → bypass
      gate.cycle() -- → normal
      assert.are.equal("normal", gate.get())
    end)
  end)

  -- Module isolation

  it("fresh require after package clear starts at bypass (open-by-default)", function()
    gate.set("normal")
    local gate2 = fresh_gate()
    assert.are.equal("bypass", gate2.get())
  end)
end)

-- ---------------------------------------------------------------------------
-- neph.internal.gate_ui
-- ---------------------------------------------------------------------------

describe("neph.internal.gate_ui", function()
  before_each(function()
    gate_ui = require("neph.internal.gate_ui")
    gate_ui._reset()
  end)

  after_each(function()
    gate_ui._reset()
  end)

  -- set() – indicator placement

  it("set hold adds indicator to empty winbar", function()
    local win = vim.api.nvim_get_current_win()
    vim.wo[win].winbar = ""
    gate_ui.set("hold", win)
    assert.truthy(vim.wo[win].winbar:find("NEPH HOLD"))
  end)

  it("set bypass adds indicator to empty winbar", function()
    local win = vim.api.nvim_get_current_win()
    vim.wo[win].winbar = ""
    gate_ui.set("bypass", win)
    assert.truthy(vim.wo[win].winbar:find("NEPH BYPASS"))
  end)

  it("set appends to existing winbar content", function()
    local win = vim.api.nvim_get_current_win()
    vim.wo[win].winbar = "existing content"
    gate_ui.set("hold", win)
    local wb = vim.wo[win].winbar
    assert.truthy(wb:find("existing content"))
    assert.truthy(wb:find("NEPH HOLD"))
  end)

  it("ignores unknown gate state", function()
    local win = vim.api.nvim_get_current_win()
    local original = vim.wo[win].winbar
    gate_ui.set("unknown_state", win)
    assert.are.equal(original, vim.wo[win].winbar)
  end)

  -- clear() – restoration

  it("clear restores previous winbar", function()
    local win = vim.api.nvim_get_current_win()
    vim.wo[win].winbar = "my winbar"
    gate_ui.set("hold", win)
    gate_ui.clear()
    assert.are.equal("my winbar", vim.wo[win].winbar)
  end)

  it("clear restores empty winbar when none was set", function()
    local win = vim.api.nvim_get_current_win()
    vim.wo[win].winbar = ""
    gate_ui.set("hold", win)
    gate_ui.clear()
    assert.are.equal("", vim.wo[win].winbar)
  end)

  it("clear is a no-op when not set", function()
    -- Must not crash
    gate_ui.clear()
    gate_ui.clear()
  end)

  it("clear is idempotent", function()
    local win = vim.api.nvim_get_current_win()
    vim.wo[win].winbar = "base"
    gate_ui.set("hold", win)
    gate_ui.clear()
    gate_ui.clear()
    assert.are.equal("base", vim.wo[win].winbar)
  end)

  -- Double-set guard (Issue 4)

  it("second set does not stack indicators on top of first", function()
    local win = vim.api.nvim_get_current_win()
    vim.wo[win].winbar = "original"
    gate_ui.set("hold", win)
    -- Calling set again (e.g. hold → bypass transition without explicit clear)
    gate_ui.set("bypass", win)
    local wb = vim.wo[win].winbar
    -- Should contain BYPASS but not a double-stacked hold
    assert.truthy(wb:find("NEPH BYPASS"))
    assert.falsy(wb:find("NEPH HOLD"))
  end)

  it("after double-set, clear restores the original winbar", function()
    local win = vim.api.nvim_get_current_win()
    vim.wo[win].winbar = "original"
    gate_ui.set("hold", win)
    gate_ui.set("bypass", win)
    gate_ui.clear()
    assert.are.equal("original", vim.wo[win].winbar)
  end)

  -- _reset() clears live winbar (Issue 5)

  it("_reset clears the live indicator from the window", function()
    local win = vim.api.nvim_get_current_win()
    vim.wo[win].winbar = "base"
    gate_ui.set("hold", win)
    -- Should have indicator now
    assert.truthy(vim.wo[win].winbar:find("NEPH HOLD"))
    gate_ui._reset()
    -- After reset the winbar should be restored, not left dirty
    assert.are.equal("base", vim.wo[win].winbar)
  end)

  it("_reset when nothing is set does not crash", function()
    gate_ui._reset()
    gate_ui._reset()
  end)

  -- Invalid / stale window handles

  it("set with an invalid win handle is a no-op", function()
    -- nvim window handles are positive integers; 999999 is almost certainly invalid
    gate_ui.set("hold", 999999)
    -- Should not throw and should not change state
    gate_ui.clear() -- also must not crash
  end)
end)
