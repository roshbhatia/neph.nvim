---@diagnostic disable: undefined-global
local placeholders = require("neph.placeholders")

describe("neph.placeholders", function()
  describe("apply()", function()
    it("returns input unchanged when no tokens are present", function()
      local out = placeholders.apply("hello world", {})
      assert.equals("hello world", out)
    end)

    it("returns input unchanged for empty string", function()
      assert.equals("", placeholders.apply("", {}))
    end)

    it("returns nil input unchanged", function()
      assert.is_nil(placeholders.apply(nil, {}))
    end)

    it("expands a known token when provider returns a value", function()
      -- Inject a fake context object
      local fake_ctx = {
        ctx = { buf = 0, win = 0, row = 1, col = 1, cwd = "/", range = nil },
        cache = {},
        get = function(_self, name) -- luacheck: ignore _self
          if name == "word" then
            return "myword"
          end
          return nil
        end,
      }
      local out = placeholders.apply("fix +word please", fake_ctx)
      assert.equals("fix myword please", out)
    end)

    it("leaves unknown tokens unexpanded", function()
      local fake_ctx = {
        ctx = {},
        cache = {},
        get = function()
          return nil
        end,
      }
      local out = placeholders.apply("do +unknown thing", fake_ctx)
      assert.equals("do +unknown thing", out)
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
end)
