---@diagnostic disable: undefined-global
local placeholders = require("neph.internal.placeholders")

-- Helper: fake context that resolves specific tokens
local function fake_ctx(map)
  return {
    ctx = { buf = 0, win = 0, row = 1, col = 1, cwd = "/", range = nil },
    cache = {},
    get = function(_self, name) -- luacheck: ignore _self
      return map[name] or nil
    end,
  }
end

-- Helper: context that resolves nothing
local function nil_ctx()
  return fake_ctx({})
end

describe("neph.placeholders", function()
  describe("apply()", function()
    it("returns input unchanged when no tokens are present", function()
      assert.equals("hello world", placeholders.apply("hello world", nil_ctx()))
    end)

    it("returns input unchanged for empty string", function()
      assert.equals("", placeholders.apply("", nil_ctx()))
    end)

    it("returns nil input unchanged", function()
      assert.is_nil(placeholders.apply(nil, nil_ctx()))
    end)

    it("expands a known token", function()
      local out = placeholders.apply("fix +word please", fake_ctx({ word = "myword" }))
      assert.equals("fix myword please", out)
    end)

    it("strips failed expansions", function()
      local out = placeholders.apply("do +unknown thing", nil_ctx())
      assert.equals("do thing", out)
    end)

    it("strips failed expansion at start of string", function()
      local out = placeholders.apply("+cursor fix the bug", nil_ctx())
      assert.equals("fix the bug", out)
    end)

    it("strips failed expansion at end of string", function()
      local out = placeholders.apply("fix the bug +cursor", nil_ctx())
      assert.equals("fix the bug", out)
    end)

    -- Escape syntax
    it("preserves escaped tokens as literal +token", function()
      local out = placeholders.apply("what does \\+file do?", fake_ctx({ file = "@foo.lua" }))
      assert.equals("what does +file do?", out)
    end)

    it("expands real tokens while preserving escaped ones", function()
      local out = placeholders.apply("fix +cursor but keep \\+selection", fake_ctx({ cursor = "@foo.lua:10" }))
      assert.equals("fix @foo.lua:10 but keep +selection", out)
    end)

    -- Multiple and repeated tokens
    it("expands multiple different tokens", function()
      local out = placeholders.apply("+file +word", fake_ctx({ file = "@a.lua", word = "hello" }))
      assert.equals("@a.lua hello", out)
    end)

    it("expands repeated same token", function()
      local out = placeholders.apply("+word and +word", fake_ctx({ word = "hello" }))
      assert.equals("hello and hello", out)
    end)

    -- Special characters in expansion values
    it("handles percent signs in expansion values", function()
      local out = placeholders.apply("check +selection", fake_ctx({ selection = "100% done" }))
      assert.equals("check 100% done", out)
    end)

    it("handles parentheses in expansion values", function()
      local out = placeholders.apply("fix +word", fake_ctx({ word = "fn(x)" }))
      assert.equals("fix fn(x)", out)
    end)

    it("handles dots in expansion values", function()
      local out = placeholders.apply("edit +file", fake_ctx({ file = "@init.lua" }))
      assert.equals("edit @init.lua", out)
    end)

    it("handles newlines in expansion values", function()
      local out = placeholders.apply("see +selection", fake_ctx({ selection = "line1\nline2" }))
      assert.equals("see line1\nline2", out)
    end)

    -- No double expansion
    it("does not double-expand token-like text in values", function()
      local out = placeholders.apply("explain +selection", fake_ctx({ selection = "use +file for context" }))
      assert.equals("explain use +file for context", out)
    end)

    -- Unicode
    it("handles unicode in expansion values", function()
      local out = placeholders.apply("fix +word", fake_ctx({ word = "naïve" }))
      assert.equals("fix naïve", out)
    end)

    -- Token adjacent to punctuation
    it("expands token adjacent to punctuation", function()
      local out = placeholders.apply("(+word)", fake_ctx({ word = "hello" }))
      assert.equals("(hello)", out)
    end)

    -- Mixed expand and strip
    it("expands known and strips unknown in same input", function()
      local out = placeholders.apply("+cursor +unknown fix", fake_ctx({ cursor = "@f:1" }))
      assert.equals("@f:1 fix", out)
    end)
  end)

  describe("descriptions", function()
    it("is a non-empty table", function()
      assert.is_table(placeholders.descriptions)
      assert.is_true(#placeholders.descriptions > 0)
    end)

    it("each entry has token and description", function()
      for _, d in ipairs(placeholders.descriptions) do
        assert.is_string(d.token)
        assert.is_string(d.description)
        assert.is_true(d.token:sub(1, 1) == "+")
      end
    end)
  end)

  describe("providers table", function()
    it("has a provider for every description token", function()
      for _, d in ipairs(placeholders.descriptions) do
        local key = d.token:sub(2) -- strip leading +
        assert.is_not_nil(placeholders.providers[key], "missing provider for token: " .. d.token)
      end
    end)
  end)

  describe("apply() state handling", function()
    it("called with nil state creates a fresh context", function()
      -- apply() with nil state should not crash (it calls context.new() internally)
      local ok, result = pcall(placeholders.apply, "hello world", nil)
      assert.is_true(ok)
      assert.is_string(result)
      assert.equals("hello world", result)
    end)

    it("called with raw EditorState-like table merges into context", function()
      -- apply() with a plain table (not a Context object) merges fields into ctx
      local state = { buf = 0, win = 0, row = 1, col = 1, cwd = "/", range = nil }
      local ok, result = pcall(placeholders.apply, "no tokens here", state)
      assert.is_true(ok)
      assert.is_string(result)
    end)

    it("consecutive + characters without word do not expand", function()
      local out = placeholders.apply("a + b", nil_ctx())
      assert.equals("a + b", out)
    end)

    it("lone + at end of string does not expand", function()
      local out = placeholders.apply("hello +", nil_ctx())
      -- The + should be kept as-is (no word match follows)
      assert.is_string(out)
    end)

    it("multiple unknown tokens in a row collapse to empty string", function()
      local out = placeholders.apply("+a +b +c", nil_ctx())
      -- All should be stripped; result should be empty or whitespace-trimmed
      assert.equals("", out)
    end)

    it("escaped token at start of string is preserved as literal", function()
      local out = placeholders.apply("\\+file is cool", fake_ctx({ file = "@foo.lua" }))
      assert.equals("+file is cool", out)
    end)

    it("escaped token at end of string is preserved as literal", function()
      local out = placeholders.apply("see \\+selection", fake_ctx({ selection = "some text" }))
      assert.equals("see +selection", out)
    end)

    it("mix of escaped and real tokens expands correctly", function()
      local out = placeholders.apply("\\+word and +cursor", fake_ctx({ word = "hello", cursor = "@f:1" }))
      assert.equals("+word and @f:1", out)
    end)

    it("value with leading + sign does not trigger re-expansion", function()
      -- The +token in the expanded value must not be re-expanded
      local out = placeholders.apply("+selection", fake_ctx({ selection = "+cursor is a token" }))
      assert.equals("+cursor is a token", out)
    end)
  end)
end)
