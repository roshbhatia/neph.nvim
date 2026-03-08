-- Fuzz / edge-case tests for the review engine.
-- Exercises compute_hunks and apply_decisions with adversarial inputs.

return function(t)
  t.describe("review engine fuzz", function()
    local engine = require("neph.api.review.engine")

    -- compute_hunks edge cases

    t.it("empty old and new → no hunks", function()
      local hunks = engine.compute_hunks({}, {})
      t.assert_eq(#hunks, 0, "no hunks for empty files")
    end)

    t.it("identical content → no hunks", function()
      local lines = { "line1", "line2", "line3" }
      local hunks = engine.compute_hunks(lines, lines)
      t.assert_eq(#hunks, 0, "no hunks for identical content")
    end)

    t.it("empty old, non-empty new → one hunk (new file)", function()
      local hunks = engine.compute_hunks({}, { "new content" })
      t.assert_truthy(#hunks > 0, "should detect addition")
    end)

    t.it("non-empty old, empty new → one hunk (delete all)", function()
      local hunks = engine.compute_hunks({ "old content" }, {})
      t.assert_truthy(#hunks > 0, "should detect deletion")
    end)

    t.it("single char change", function()
      local old = { "abc" }
      local new = { "axc" }
      local hunks = engine.compute_hunks(old, new)
      t.assert_truthy(#hunks > 0, "should detect single char change")
    end)

    t.it("many hunks in large file", function()
      local old = {}
      local new = {}
      for i = 1, 200 do
        table.insert(old, "line " .. i)
        if i % 10 == 0 then
          table.insert(new, "CHANGED " .. i)
        else
          table.insert(new, "line " .. i)
        end
      end
      local hunks = engine.compute_hunks(old, new)
      t.assert_truthy(#hunks >= 10, "should detect multiple scattered changes")
    end)

    -- apply_decisions edge cases

    t.it("accept all hunks → result matches new content", function()
      local old = { "a", "b", "c" }
      local new = { "a", "B", "c" }
      local hunks = engine.compute_hunks(old, new)
      local decisions = {}
      for i = 1, #hunks do
        table.insert(decisions, { index = i, decision = "accept" })
      end
      local result = engine.apply_decisions(old, new, decisions)
      t.assert_eq(result, table.concat(new, "\n"), "accept all should produce new content")
    end)

    t.it("reject all hunks → result matches old content", function()
      local old = { "a", "b", "c" }
      local new = { "a", "B", "c" }
      local hunks = engine.compute_hunks(old, new)
      local decisions = {}
      for i = 1, #hunks do
        table.insert(decisions, { index = i, decision = "reject" })
      end
      local result = engine.apply_decisions(old, new, decisions)
      t.assert_eq(result, table.concat(old, "\n"), "reject all should preserve old content")
    end)

    t.it("empty decisions list → result matches old content", function()
      local old = { "a", "b" }
      local new = { "x", "y" }
      local result = engine.apply_decisions(old, new, {})
      t.assert_eq(result, table.concat(old, "\n"), "no decisions should preserve old")
    end)

    t.it("partial accept on multi-hunk diff", function()
      local old = { "line1", "line2", "line3", "line4" }
      local new = { "LINE1", "line2", "LINE3", "line4" }
      local hunks = engine.compute_hunks(old, new)
      if #hunks >= 2 then
        local decisions = {
          { index = 1, decision = "accept" },
          { index = 2, decision = "reject" },
        }
        local result = engine.apply_decisions(old, new, decisions)
        local lines = vim.split(result, "\n", { plain = true })
        t.assert_eq(lines[1], "LINE1", "first hunk accepted")
        t.assert_eq(lines[3], "line3", "second hunk rejected")
      end
    end)

    t.it("insertion hunk (new lines added)", function()
      local old = { "a", "c" }
      local new = { "a", "b", "c" }
      local hunks = engine.compute_hunks(old, new)
      t.assert_truthy(#hunks > 0, "should detect insertion")
      local decisions = {}
      for i = 1, #hunks do
        table.insert(decisions, { index = i, decision = "accept" })
      end
      local result = engine.apply_decisions(old, new, decisions)
      t.assert_eq(result, "a\nb\nc", "insertion should be applied")
    end)

    t.it("deletion hunk (lines removed)", function()
      local old = { "a", "b", "c" }
      local new = { "a", "c" }
      local hunks = engine.compute_hunks(old, new)
      t.assert_truthy(#hunks > 0, "should detect deletion")
      local decisions = {}
      for i = 1, #hunks do
        table.insert(decisions, { index = i, decision = "accept" })
      end
      local result = engine.apply_decisions(old, new, decisions)
      t.assert_eq(result, "a\nc", "deletion should be applied")
    end)

    -- build_envelope edge cases

    t.it("all accept → decision is 'accept'", function()
      local decisions = {
        { index = 1, decision = "accept" },
        { index = 2, decision = "accept" },
      }
      local env = engine.build_envelope(decisions, "content")
      t.assert_eq(env.decision, "accept")
    end)

    t.it("all reject → decision is 'reject', content empty", function()
      local decisions = {
        { index = 1, decision = "reject", reason = "bad" },
      }
      local env = engine.build_envelope(decisions, "content")
      t.assert_eq(env.decision, "reject")
      t.assert_eq(env.content, "")
    end)

    t.it("mixed → decision is 'partial'", function()
      local decisions = {
        { index = 1, decision = "accept" },
        { index = 2, decision = "reject", reason = "nope" },
      }
      local env = engine.build_envelope(decisions, "content")
      t.assert_eq(env.decision, "partial")
      t.assert_truthy(env.reason:find("nope"), "reason should include rejection reason")
    end)

    t.it("empty decisions → decision is 'accept' (no changes)", function()
      local env = engine.build_envelope({}, "content")
      t.assert_eq(env.decision, "accept")
    end)

    -- Session state machine

    t.it("session finalize produces valid envelope", function()
      local session = engine.create_session({ "a", "b" }, { "a", "B" })
      session.accept()
      local env = session.finalize()
      t.assert_eq(env.schema, "review/v1")
      t.assert_eq(env.decision, "accept")
      t.assert_truthy(env.content:find("B"), "content should have accepted change")
    end)

    t.it("session handles accept_all on multi-hunk", function()
      local old = {}
      local new = {}
      for i = 1, 50 do
        table.insert(old, "line" .. i)
        table.insert(new, "LINE" .. i)
      end
      local session = engine.create_session(old, new)
      session.accept_all()
      t.assert_truthy(session.is_done(), "should be done after accept_all")
      local env = session.finalize()
      t.assert_eq(env.decision, "accept")
    end)

    t.it("session handles reject_all", function()
      local session = engine.create_session({ "a" }, { "b" })
      session.reject_all("no good")
      t.assert_truthy(session.is_done())
      local env = session.finalize()
      t.assert_eq(env.decision, "reject")
    end)

    t.it("accept/reject past end is no-op", function()
      local session = engine.create_session({ "a" }, { "b" })
      session.accept()
      t.assert_truthy(session.is_done())
      local r1 = session.accept()
      local r2 = session.reject()
      t.assert_eq(r1, false, "accept past end returns false")
      t.assert_eq(r2, false, "reject past end returns false")
    end)
  end)
end
