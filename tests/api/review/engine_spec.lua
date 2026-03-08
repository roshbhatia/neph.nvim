local engine = require("neph.api.review.engine")

describe("neph.api.review.engine", function()
  describe("compute_hunks", function()
    it("returns empty for identical lines", function()
      local lines = { "line 1", "line 2" }
      local hunks = engine.compute_hunks(lines, lines)
      assert.are.same({}, hunks)
    end)

    it("detects a replacement", function()
      local old = { "line 1", "old 2", "line 3" }
      local new = { "line 1", "new 2", "line 3" }
      local hunks = engine.compute_hunks(old, new)
      assert.are.same({ { start_a = 2, end_a = 2, start_b = 2, end_b = 2 } }, hunks)
    end)

    it("handles addition", function()
      local old = { "line 1" }
      local new = { "line 1", "line 2" }
      local hunks = engine.compute_hunks(old, new)
      -- Pure addition: start_a=1 (insertion after line 1), count_a=0
      -- start_b=2, count_b=1 (new line 2)
      assert.are.equal(1, #hunks)
      assert.are.equal(1, hunks[1].start_a)
      assert.are.equal(2, hunks[1].start_b)
      assert.are.equal(2, hunks[1].end_b)
    end)

    it("handles deletion", function()
      local old = { "line 1", "line 2", "line 3" }
      local new = { "line 1", "line 3" }
      local hunks = engine.compute_hunks(old, new)
      assert.are.equal(1, #hunks)
      assert.are.equal(2, hunks[1].start_a)
      assert.are.equal(2, hunks[1].end_a)
    end)

    it("handles multi-line replacement with different counts", function()
      local old = { "A", "B", "C" }
      local new = { "A", "X", "Y", "Z", "C" }
      local hunks = engine.compute_hunks(old, new)
      assert.are.equal(1, #hunks)
      assert.are.equal(2, hunks[1].start_a)
      assert.are.equal(2, hunks[1].end_a)
      assert.are.equal(2, hunks[1].start_b)
      assert.are.equal(4, hunks[1].end_b)
    end)
  end)

  describe("apply_decisions", function()
    it("applies accepted hunks", function()
      local old = { "line 1", "old 2", "line 3" }
      local new = { "line 1", "new 2", "line 3" }
      local decisions = { { index = 1, decision = "accept" } }
      local result = engine.apply_decisions(old, new, decisions)
      assert.are.same("line 1\nnew 2\nline 3", result)
    end)

    it("ignores rejected hunks", function()
      local old = { "line 1", "old 2", "line 3" }
      local new = { "line 1", "new 2", "line 3" }
      local decisions = { { index = 1, decision = "reject" } }
      local result = engine.apply_decisions(old, new, decisions)
      assert.are.same("line 1\nold 2\nline 3", result)
    end)

    it("applies multiple changes correctly with offset", function()
      local old = { "A", "B", "C" }
      local new = { "A", "B1", "B2", "C" }
      local hunks = engine.compute_hunks(old, new)
      assert.are.equal(1, #hunks)

      local decisions = { { index = 1, decision = "accept" } }
      local result = engine.apply_decisions(old, new, decisions)
      assert.are.same("A\nB1\nB2\nC", result)
    end)
  end)

  describe("state machine", function()
    it("manages a review session", function()
      local old = { "line 1", "old 2", "line 3", "old 4" }
      local new = { "line 1", "new 2", "line 3", "new 4" }
      local session = engine.create_session(old, new)

      assert.are.equal(2, session.get_total_hunks())
      assert.is_false(session.is_done())

      local _, idx = session.get_current_hunk()
      assert.are.equal(1, idx)

      session.accept()
      assert.is_false(session.is_done())

      _, idx = session.get_current_hunk()
      assert.are.equal(2, idx)

      session.reject("not good")
      assert.is_true(session.is_done())

      local envelope = session.finalize()
      assert.are.equal("partial", envelope.decision)
      assert.are.equal("line 1\nnew 2\nline 3\nold 4", envelope.content)
      assert.are.equal("not good", envelope.reason)
    end)

    it("accept_all works", function()
      local old = { "A", "B" }
      local new = { "A1", "B1" }
      local session = engine.create_session(old, new)
      session.accept_all()
      assert.is_true(session.is_done())
      local envelope = session.finalize()
      assert.are.equal("accept", envelope.decision)
      assert.are.equal("A1\nB1", envelope.content)
    end)

    it("reject_all works", function()
      local old = { "A", "B" }
      local new = { "A1", "B1" }
      local session = engine.create_session(old, new)
      session.reject_all("reason")
      assert.is_true(session.is_done())
      local envelope = session.finalize()
      assert.are.equal("reject", envelope.decision)
      assert.are.equal("", envelope.content)
      assert.are.equal("reason", envelope.reason)
    end)
  end)

  describe("build_envelope", function()
    it("all accepted → decision=accept, content preserved, no reason", function()
      local decisions = {
        { index = 1, decision = "accept" },
        { index = 2, decision = "accept" },
      }
      local envelope = engine.build_envelope(decisions, "new content")
      assert.are.equal("accept", envelope.decision)
      assert.are.equal("new content", envelope.content)
      assert.is_nil(envelope.reason)
      assert.are.equal("review/v1", envelope.schema)
    end)

    it("all rejected → decision=reject, content='', reason collected", function()
      local decisions = {
        { index = 1, decision = "reject", reason = "bad style" },
        { index = 2, decision = "reject", reason = "wrong logic" },
      }
      local envelope = engine.build_envelope(decisions, "new content")
      assert.are.equal("reject", envelope.decision)
      assert.are.equal("", envelope.content)
      assert.are.equal("bad style; wrong logic", envelope.reason)
    end)

    it("mixed decisions → decision=partial, content preserved, reasons from rejects", function()
      local decisions = {
        { index = 1, decision = "accept" },
        { index = 2, decision = "reject", reason = "nope" },
      }
      local envelope = engine.build_envelope(decisions, "partial content")
      assert.are.equal("partial", envelope.decision)
      assert.are.equal("partial content", envelope.content)
      assert.are.equal("nope", envelope.reason)
    end)

    it("empty decisions list → decision=accept", function()
      local envelope = engine.build_envelope({}, "unchanged")
      assert.are.equal("accept", envelope.decision)
      assert.are.equal("unchanged", envelope.content)
      assert.is_nil(envelope.reason)
    end)

    it("rejected with empty/nil reasons → reason is nil", function()
      local decisions = {
        { index = 1, decision = "reject", reason = "" },
        { index = 2, decision = "reject" },
      }
      local envelope = engine.build_envelope(decisions, "content")
      assert.are.equal("reject", envelope.decision)
      assert.is_nil(envelope.reason)
    end)
  end)

  describe("random-access session", function()
    -- Helper: produces N separate hunks by interleaving unchanged lines
    -- e.g. 4 hunks: old={A,sep,B,sep,C,sep,D} new={W,sep,X,sep,Y,sep,Z}
    local function make_multi_hunk(n)
      local old, new = {}, {}
      for i = 1, n do
        old[#old + 1] = "old_" .. i
        new[#new + 1] = "new_" .. i
        if i < n then
          old[#old + 1] = "sep_" .. i
          new[#new + 1] = "sep_" .. i
        end
      end
      return old, new
    end

    it("accept_at out of order", function()
      local old, new = make_multi_hunk(4)
      local session = engine.create_session(old, new)
      assert.are.equal(4, session.get_total_hunks())

      -- Accept hunk 3 first, then hunk 1
      assert.is_true(session.accept_at(3))
      assert.is_true(session.accept_at(1))

      local d1 = session.get_decision(1)
      local d3 = session.get_decision(3)
      assert.are.equal("accept", d1.decision)
      assert.are.equal("accept", d3.decision)
      -- Hunk 2 and 4 still undecided
      assert.is_nil(session.get_decision(2))
      assert.is_nil(session.get_decision(4))
    end)

    it("reject_at with reason", function()
      local old = { "A" }
      local new = { "B" }
      local session = engine.create_session(old, new)
      assert.is_true(session.reject_at(1, "bad change"))
      local d = session.get_decision(1)
      assert.are.equal("reject", d.decision)
      assert.are.equal("bad change", d.reason)
    end)

    it("accept_at/reject_at returns false for out-of-bounds", function()
      local old = { "A" }
      local new = { "B" }
      local session = engine.create_session(old, new)
      assert.is_false(session.accept_at(0))
      assert.is_false(session.accept_at(2))
      assert.is_false(session.reject_at(0))
      assert.is_false(session.reject_at(2))
    end)

    it("is_complete with mixed states", function()
      local old, new = make_multi_hunk(3)
      local session = engine.create_session(old, new)
      assert.are.equal(3, session.get_total_hunks())

      assert.is_false(session.is_complete())
      session.accept_at(1)
      assert.is_false(session.is_complete())
      session.reject_at(2, "nope")
      assert.is_false(session.is_complete())
      session.accept_at(3)
      assert.is_true(session.is_complete())
    end)

    it("next_undecided finds first gap", function()
      local old, new = make_multi_hunk(4)
      local session = engine.create_session(old, new)
      assert.are.equal(4, session.get_total_hunks())

      assert.are.equal(1, session.next_undecided())
      session.accept_at(1)
      assert.are.equal(2, session.next_undecided())
      session.accept_at(2)
      assert.are.equal(3, session.next_undecided())
      session.accept_at(4) -- skip 3
      assert.are.equal(3, session.next_undecided())
      session.accept_at(3)
      assert.is_nil(session.next_undecided())
    end)

    it("next_undecided wraps around from given position", function()
      local old, new = make_multi_hunk(3)
      local session = engine.create_session(old, new)
      assert.are.equal(3, session.get_total_hunks())

      session.accept_at(2)
      session.accept_at(3)
      -- Starting from 2, should wrap and find 1
      assert.are.equal(1, session.next_undecided(2))
    end)

    it("finalize treats undecided as rejected", function()
      local old, new = make_multi_hunk(3)
      local session = engine.create_session(old, new)
      assert.are.equal(3, session.get_total_hunks())

      session.accept_at(1)
      -- Leave 2 and 3 undecided
      local envelope = session.finalize()
      assert.are.equal("partial", envelope.decision)
      -- Hunks 2 and 3 should be rejected with "Undecided"
      assert.are.equal("reject", envelope.hunks[2].decision)
      assert.are.equal("Undecided", envelope.hunks[2].reason)
      assert.are.equal("reject", envelope.hunks[3].decision)
    end)

    it("accept_all_remaining skips already-decided", function()
      local old, new = make_multi_hunk(3)
      local session = engine.create_session(old, new)
      assert.are.equal(3, session.get_total_hunks())

      session.reject_at(2, "keep this rejected")
      session.accept_all_remaining()
      assert.is_true(session.is_complete())

      local d1 = session.get_decision(1)
      local d2 = session.get_decision(2)
      local d3 = session.get_decision(3)
      assert.are.equal("accept", d1.decision)
      assert.are.equal("reject", d2.decision)
      assert.are.equal("keep this rejected", d2.reason)
      assert.are.equal("accept", d3.decision)
    end)

    it("reject_all_remaining skips already-decided", function()
      local old, new = make_multi_hunk(3)
      local session = engine.create_session(old, new)
      assert.are.equal(3, session.get_total_hunks())

      session.accept_at(1)
      session.reject_all_remaining("bulk reject")
      assert.is_true(session.is_complete())

      assert.are.equal("accept", session.get_decision(1).decision)
      assert.are.equal("reject", session.get_decision(2).decision)
      assert.are.equal("bulk reject", session.get_decision(2).reason)
      assert.are.equal("reject", session.get_decision(3).decision)
    end)

    it("sequential methods still work (backward compat)", function()
      local old, new = make_multi_hunk(2)
      local session = engine.create_session(old, new)
      assert.are.equal(2, session.get_total_hunks())

      session.accept()
      session.reject("no")
      assert.is_true(session.is_done())
      assert.is_true(session.is_complete())

      local d1 = session.get_decision(1)
      local d2 = session.get_decision(2)
      assert.are.equal("accept", d1.decision)
      assert.are.equal("reject", d2.decision)
    end)

    it("get_hunk_ranges returns all ranges", function()
      local old, new = make_multi_hunk(3)
      local session = engine.create_session(old, new)
      local ranges = session.get_hunk_ranges()
      assert.are.equal(session.get_total_hunks(), #ranges)
    end)
  end)

  describe("state machine edge cases", function()
    it("no hunks (identical input) → is_done immediately, finalize gives accept", function()
      local lines = { "same", "lines" }
      local session = engine.create_session(lines, lines)
      assert.is_true(session.is_done())
      assert.are.equal(0, session.get_total_hunks())
      local envelope = session.finalize()
      assert.are.equal("accept", envelope.decision)
    end)

    it("single hunk accept → decision=accept", function()
      local old = { "A" }
      local new = { "B" }
      local session = engine.create_session(old, new)
      session.accept()
      assert.is_true(session.is_done())
      local envelope = session.finalize()
      assert.are.equal("accept", envelope.decision)
      assert.are.equal("B", envelope.content)
    end)

    it("single hunk reject → decision=reject, content=''", function()
      local old = { "A" }
      local new = { "B" }
      local session = engine.create_session(old, new)
      session.reject("no thanks")
      assert.is_true(session.is_done())
      local envelope = session.finalize()
      assert.are.equal("reject", envelope.decision)
      assert.are.equal("", envelope.content)
    end)

    it("accept() past end returns false", function()
      local old = { "A" }
      local new = { "B" }
      local session = engine.create_session(old, new)
      session.accept()
      assert.is_true(session.is_done())
      assert.is_false(session.accept())
    end)

    it("reject() past end returns false", function()
      local old = { "A" }
      local new = { "B" }
      local session = engine.create_session(old, new)
      session.reject("reason")
      assert.is_true(session.is_done())
      assert.is_false(session.reject("another"))
    end)

    it("reject_all with reason only applies reason to first hunk", function()
      local old = { "A", "B", "C" }
      local new = { "X", "Y", "Z" }
      local session = engine.create_session(old, new)
      session.reject_all("first reason")
      assert.is_true(session.is_done())
      local envelope = session.finalize()
      assert.are.equal("reject", envelope.decision)
      -- Only the first hunk gets the reason; subsequent hunks get nil
      assert.are.equal("first reason", envelope.reason)
      -- Verify the underlying decisions: only the first has a reason
      local found_reasons = 0
      for _, h in ipairs(envelope.hunks) do
        if h.reason and h.reason ~= "" then
          found_reasons = found_reasons + 1
        end
      end
      assert.are.equal(1, found_reasons)
    end)
  end)
end)
