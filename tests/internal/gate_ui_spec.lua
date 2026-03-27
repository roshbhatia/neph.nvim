---@diagnostic disable: undefined-global
-- Tests for lua/neph/internal/gate_ui.lua

local gate_ui = require("neph.internal.gate_ui")

describe("neph.internal.gate_ui", function()
  before_each(function()
    gate_ui._reset()
  end)

  after_each(function()
    gate_ui._reset()
  end)

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

  it("set appends to existing winbar", function()
    local win = vim.api.nvim_get_current_win()
    vim.wo[win].winbar = "existing content"
    gate_ui.set("hold", win)
    local wb = vim.wo[win].winbar
    assert.truthy(wb:find("existing content"))
    assert.truthy(wb:find("NEPH HOLD"))
  end)

  it("clear restores previous winbar", function()
    local win = vim.api.nvim_get_current_win()
    vim.wo[win].winbar = "my winbar"
    gate_ui.set("hold", win)
    gate_ui.clear()
    assert.are.equal("my winbar", vim.wo[win].winbar)
  end)

  it("clear is a no-op when not set", function()
    -- Should not crash
    gate_ui.clear()
    gate_ui.clear()
  end)
end)
