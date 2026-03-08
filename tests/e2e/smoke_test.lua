-- Smoke test: verify plugin loads and basic setup works.

return function(t)
  t.describe("smoke", function()
    t.it("require('neph') loads without error", function()
      local neph = require("neph")
      t.assert_truthy(neph, "neph module should load")
      t.assert_truthy(neph.setup, "neph.setup should exist")
    end)

    t.it("neph.setup() completes without error", function()
      local stub_backend = {
        setup = function() end,
        open = function(_, ac, _)
          return { pane_id = 1, cmd = ac.cmd, cwd = "/tmp", name = "stub" }
        end,
        focus = function()
          return true
        end,
        hide = function(td)
          td.pane_id = nil
        end,
        is_visible = function(td)
          return td ~= nil and td.pane_id ~= nil
        end,
        kill = function(td)
          td.pane_id = nil
        end,
        cleanup_all = function() end,
      }
      require("neph").setup({
        agents = { require("neph.agents.claude") },
        backend = stub_backend,
      })
    end)

    t.it("agents.get_all() returns a table", function()
      local agents = require("neph.internal.agents")
      local all = agents.get_all()
      t.assert_eq(type(all), "table", "get_all() should return a table")
    end)
  end)
end
