-- Smoke test: verify plugin loads and basic setup works.

return function(t)
  t.describe("smoke", function()
    t.it("require('neph') loads without error", function()
      local neph = require("neph")
      t.assert_truthy(neph, "neph module should load")
      t.assert_truthy(neph.setup, "neph.setup should exist")
    end)

    t.it("neph.setup() completes without error", function()
      require("neph").setup()
    end)

    t.it("agents.get_all() returns a table", function()
      local agents = require("neph.internal.agents")
      local all = agents.get_all()
      t.assert_eq(type(all), "table", "get_all() should return a table")
    end)
  end)
end
