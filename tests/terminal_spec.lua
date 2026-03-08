local terminal = require("neph.internal.terminal")

describe("neph.internal.terminal", function()
  before_each(function()
    -- Reset module state by clearing the cache
    package.loaded["neph.internal.terminal"] = nil
    terminal = require("neph.internal.terminal")
  end)

  describe("get_last_prompt / set_last_prompt", function()
    it("returns nil for unknown termname", function()
      assert.is_nil(terminal.get_last_prompt("nonexistent"))
    end)

    it("round-trips a prompt", function()
      terminal.set_last_prompt("claude", "fix the bug")
      assert.are.equal("fix the bug", terminal.get_last_prompt("claude"))
    end)

    it("overwrites previous prompt", function()
      terminal.set_last_prompt("claude", "first prompt")
      terminal.set_last_prompt("claude", "second prompt")
      assert.are.equal("second prompt", terminal.get_last_prompt("claude"))
    end)

    it("maintains separate prompts per agent", function()
      terminal.set_last_prompt("claude", "claude prompt")
      terminal.set_last_prompt("gemini", "gemini prompt")
      assert.are.equal("claude prompt", terminal.get_last_prompt("claude"))
      assert.are.equal("gemini prompt", terminal.get_last_prompt("gemini"))
    end)

    it("handles empty string prompts", function()
      terminal.set_last_prompt("claude", "")
      assert.are.equal("", terminal.get_last_prompt("claude"))
    end)

    it("handles multiline prompts", function()
      terminal.set_last_prompt("claude", "line1\nline2\nline3")
      assert.are.equal("line1\nline2\nline3", terminal.get_last_prompt("claude"))
    end)
  end)
end)
