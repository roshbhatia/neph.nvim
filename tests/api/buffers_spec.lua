---@diagnostic disable: undefined-global
local buffers = require("neph.api.buffers")

describe("neph.api.buffers", function()
  it("checktime returns ok", function()
    local result = buffers.checktime()
    assert.is_truthy(result.ok)
  end)

  it("close_tab does not error on single tab", function()
    -- With the last-tab guard, this should succeed without error
    local result = buffers.close_tab()
    assert.is_truthy(result.ok)
  end)

  it("checktime accepts nil params without error", function()
    local result = buffers.checktime(nil)
    assert.is_truthy(result.ok)
  end)

  it("close_tab accepts nil params without error", function()
    local result = buffers.close_tab(nil)
    assert.is_truthy(result.ok)
  end)

  it("close_tab returns ok=true when only one tab exists (guard active)", function()
    -- Ensure we have exactly one tab before calling close_tab
    while #vim.api.nvim_list_tabpages() > 1 do
      vim.cmd("tabclose")
    end
    assert.equals(1, #vim.api.nvim_list_tabpages())
    local result = buffers.close_tab()
    assert.is_truthy(result.ok)
    -- Should still have one tab (guard prevented close)
    assert.equals(1, #vim.api.nvim_list_tabpages())
  end)

  it("checktime result has ok field as boolean", function()
    local result = buffers.checktime()
    assert.is_boolean(result.ok)
  end)

  it("close_tab result has ok field as boolean", function()
    local result = buffers.close_tab()
    assert.is_boolean(result.ok)
  end)

  describe("close_tab() with multiple tabs", function()
    it("closes tab when multiple tabs exist and returns ok=true", function()
      -- Open a second tab so tabclose is allowed
      vim.cmd("tabnew")
      assert.equals(2, #vim.api.nvim_list_tabpages())
      local result = buffers.close_tab()
      assert.is_truthy(result.ok)
      -- After a successful close we should be back to one tab
      assert.equals(1, #vim.api.nvim_list_tabpages())
    end)
  end)

  describe("checktime() error path", function()
    it("returns ok=false when vim.cmd raises", function()
      local orig = vim.cmd
      vim.cmd = function(cmd)
        if cmd == "checktime" then
          error("forced checktime error")
        end
        return orig(cmd)
      end
      local result = buffers.checktime()
      vim.cmd = orig
      assert.is_false(result.ok)
      assert.is_not_nil(result.error)
      assert.equals("CHECKTIME_FAILED", result.error.code)
    end)
  end)
end)
