local ui = require("neph.api.review.ui")

describe("neph.api.review.ui", function()
  describe("find_hunk_at_cursor", function()
    local hunks = {
      { start_a = 3, end_a = 5, start_b = 3, end_b = 5 },
      { start_a = 10, end_a = 12, start_b = 10, end_b = 12 },
      { start_a = 20, end_a = 20, start_b = 20, end_b = 22 },
    }

    it("returns exact match when cursor is within a hunk", function()
      assert.are.equal(1, ui.find_hunk_at_cursor(hunks, 3))
      assert.are.equal(1, ui.find_hunk_at_cursor(hunks, 4))
      assert.are.equal(1, ui.find_hunk_at_cursor(hunks, 5))
      assert.are.equal(2, ui.find_hunk_at_cursor(hunks, 10))
      assert.are.equal(2, ui.find_hunk_at_cursor(hunks, 12))
      assert.are.equal(3, ui.find_hunk_at_cursor(hunks, 20))
    end)

    it("returns nearest hunk when cursor is between hunks", function()
      -- Line 7 is between hunk 1 (3-5) and hunk 2 (10-12), closer to hunk 1
      assert.are.equal(1, ui.find_hunk_at_cursor(hunks, 7))
      -- Line 8 is equidistant or closer to hunk 2
      assert.are.equal(2, ui.find_hunk_at_cursor(hunks, 8))
      -- Line 15 is between hunk 2 (10-12) and hunk 3 (20), closer to hunk 2
      assert.are.equal(2, ui.find_hunk_at_cursor(hunks, 15))
    end)

    it("returns nearest for cursor before first hunk", function()
      assert.are.equal(1, ui.find_hunk_at_cursor(hunks, 1))
    end)

    it("returns nearest for cursor after last hunk", function()
      assert.are.equal(3, ui.find_hunk_at_cursor(hunks, 30))
    end)

    it("returns 1 for empty hunks", function()
      assert.are.equal(1, ui.find_hunk_at_cursor({}, 5))
    end)

    it("handles single-line hunks", function()
      local single = {
        { start_a = 5, end_a = 5, start_b = 5, end_b = 5 },
      }
      assert.are.equal(1, ui.find_hunk_at_cursor(single, 5))
      assert.are.equal(1, ui.find_hunk_at_cursor(single, 3))
    end)
  end)

  describe("build_winbar", function()
    local keymaps = {
      accept = "<localleader>a",
      reject = "<localleader>r",
      accept_all = "<localleader>A",
      reject_all = "<localleader>R",
      undo = "<localleader>u",
      submit = "<CR>",
      quit = "q",
    }

    it("shows undecided for nil decision", function()
      local bar = ui.build_winbar(2, 5, nil, keymaps)
      assert.truthy(bar:find("Hunk 2/5"))
      assert.truthy(bar:find("undecided"))
      assert.truthy(bar:find("<localleader>a=accept"))
    end)

    it("shows accepted for accept decision", function()
      local bar = ui.build_winbar(1, 3, { decision = "accept" }, keymaps)
      assert.truthy(bar:find("accepted"))
      assert.truthy(bar:find("DiagnosticOk"))
    end)

    it("shows rejected for reject decision", function()
      local bar = ui.build_winbar(1, 3, { decision = "reject" }, keymaps)
      assert.truthy(bar:find("rejected"))
      assert.truthy(bar:find("DiagnosticError"))
    end)

    it("shows reason for reject with reason", function()
      local bar = ui.build_winbar(1, 3, { decision = "reject", reason = "too verbose" }, keymaps)
      assert.truthy(bar:find("rejected: too verbose"))
    end)

    it("includes submit keymap in display", function()
      local bar = ui.build_winbar(1, 1, nil, keymaps)
      assert.truthy(bar:find("<CR>=submit"))
      assert.truthy(bar:find("q=quit"))
    end)

    it("uses custom keymaps in display", function()
      local custom = {
        accept = "<leader>a",
        reject = "<leader>r",
        accept_all = "<leader>A",
        reject_all = "<leader>R",
        undo = "<leader>u",
        submit = "<leader>s",
        quit = "<leader>q",
      }
      local bar = ui.build_winbar(1, 1, nil, custom)
      assert.truthy(bar:find("<leader>a=accept"))
      assert.truthy(bar:find("<leader>s=submit"))
      assert.truthy(bar:find("<leader>q=quit"))
    end)

    it("includes tally when provided", function()
      local tally = { accepted = 3, rejected = 1, undecided = 2 }
      local bar = ui.build_winbar(1, 6, nil, keymaps, tally)
      assert.truthy(bar:find("✓3"))
      assert.truthy(bar:find("✗1"))
      assert.truthy(bar:find("?2"))
    end)

    it("works without tally", function()
      local bar = ui.build_winbar(1, 3, nil, keymaps)
      -- Should still render without error
      assert.truthy(bar:find("Hunk 1/3"))
    end)
  end)

  describe("build_right_winbar", function()
    it("shows PROPOSED with tally", function()
      local tally = { accepted = 2, rejected = 1, undecided = 0 }
      local bar = ui.build_right_winbar(tally)
      assert.truthy(bar:find("PROPOSED"))
      assert.truthy(bar:find("✓2"))
      assert.truthy(bar:find("✗1"))
      assert.truthy(bar:find("?0"))
    end)

    it("shows PROPOSED without tally", function()
      local bar = ui.build_right_winbar(nil)
      assert.truthy(bar:find("PROPOSED"))
    end)
  end)
end)
