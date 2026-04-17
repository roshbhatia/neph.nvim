---@diagnostic disable: undefined-global
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

    it("does not mutate old_lines input", function()
      local old = { "line 1", "old 2", "line 3" }
      local old_copy = { "line 1", "old 2", "line 3" }
      local new = { "line 1", "new 2", "line 3" }
      local decisions = { { index = 1, decision = "accept" } }
      engine.apply_decisions(old, new, decisions)
      assert.are.same(old_copy, old)
    end)

    it("nil/missing decision entry is treated as reject (determinism)", function()
      local old = { "A", "sep", "B" }
      local new = { "X", "sep", "Y" }
      -- Two hunks; only provide decision for hunk 2; hunk 1 missing → treated as reject
      local decisions = { nil, { index = 2, decision = "accept" } }
      local result = engine.apply_decisions(old, new, decisions)
      -- hunk 1 (A→X) rejected: keep A; hunk 2 (B→Y) accepted: use Y
      assert.are.equal("A\nsep\nY", result)
    end)

    it("apply_decisions is deterministic: same inputs always produce same output", function()
      local old = { "A", "sep", "B", "sep", "C" }
      local new = { "X", "sep", "Y", "sep", "Z" }
      local decisions = {
        { index = 1, decision = "accept" },
        { index = 2, decision = "reject" },
        { index = 3, decision = "accept" },
      }
      local r1 = engine.apply_decisions(old, new, decisions)
      local r2 = engine.apply_decisions(old, new, decisions)
      assert.are.equal(r1, r2)
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

    it("multi-hunk: accept first, reject second keeps first new and second old", function()
      -- 3 hunks separated by unchanging "sep" lines
      local old = { "old1", "sep", "old2", "sep", "old3" }
      local new = { "new1", "sep", "new2", "sep", "new3" }
      local decisions = {
        { index = 1, decision = "accept" },
        { index = 2, decision = "reject" },
        { index = 3, decision = "accept" },
      }
      local result = engine.apply_decisions(old, new, decisions)
      assert.are.equal("new1\nsep\nold2\nsep\nnew3", result)
    end)

    it("multi-hunk: reject first, accept second keeps first old and second new", function()
      local old = { "old1", "sep", "old2", "sep", "old3" }
      local new = { "new1", "sep", "new2", "sep", "new3" }
      local decisions = {
        { index = 1, decision = "reject" },
        { index = 2, decision = "accept" },
        { index = 3, decision = "reject" },
      }
      local result = engine.apply_decisions(old, new, decisions)
      assert.are.equal("old1\nsep\nnew2\nsep\nold3", result)
    end)

    it("all hunks accepted: result equals new content joined", function()
      local old = { "old1", "sep", "old2" }
      local new = { "new1", "sep", "new2" }
      local decisions = {
        { index = 1, decision = "accept" },
        { index = 2, decision = "accept" },
      }
      local result = engine.apply_decisions(old, new, decisions)
      assert.are.equal("new1\nsep\nnew2", result)
    end)

    it("all hunks rejected: result equals old content joined", function()
      local old = { "old1", "sep", "old2" }
      local new = { "new1", "sep", "new2" }
      local decisions = {
        { index = 1, decision = "reject" },
        { index = 2, decision = "reject" },
      }
      local result = engine.apply_decisions(old, new, decisions)
      assert.are.equal("old1\nsep\nold2", result)
    end)

    it("is deterministic: same inputs always yield same output", function()
      local old = { "A", "B", "C" }
      local new = { "A", "X", "C" }
      local decisions = { { index = 1, decision = "accept" } }
      local r1 = engine.apply_decisions(old, new, decisions)
      local r2 = engine.apply_decisions(old, new, decisions)
      local r3 = engine.apply_decisions(old, new, decisions)
      assert.are.equal(r1, r2)
      assert.are.equal(r2, r3)
    end)

    it("does not mutate old_lines when applying patches", function()
      local old = { "A", "B", "C" }
      local old_copy = { "A", "B", "C" }
      local new = { "A", "X", "C" }
      local decisions = { { index = 1, decision = "accept" } }
      engine.apply_decisions(old, new, decisions)
      assert.are.same(old_copy, old)
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

    it("envelope.hunks is a snapshot: mutating input decisions does not affect envelope", function()
      local decisions = {
        { index = 1, decision = "accept" },
        { index = 2, decision = "reject", reason = "bad" },
      }
      local envelope = engine.build_envelope(decisions, "content")
      -- Mutate the original decisions table after building the envelope
      decisions[1].decision = "reject"
      table.insert(decisions, { index = 3, decision = "accept" })
      -- Envelope hunks must be unchanged
      assert.are.equal(2, #envelope.hunks)
      assert.are.equal("accept", envelope.hunks[1].decision)
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

    it("next_undecided on session with 0 hunks returns nil", function()
      local session = engine.create_session({}, {})
      assert.is_nil(session.next_undecided())
      assert.is_nil(session.next_undecided(1))
      assert.is_nil(session.next_undecided(0))
    end)

    it("next_undecided on fully decided session returns nil", function()
      local old, new = make_multi_hunk(3)
      local session = engine.create_session(old, new)
      session.accept_at(1)
      session.accept_at(2)
      session.accept_at(3)
      assert.is_nil(session.next_undecided())
      assert.is_nil(session.next_undecided(1))
      assert.is_nil(session.next_undecided(4))
    end)

    it("next_undecided with out-of-bounds from clamps correctly", function()
      local old, new = make_multi_hunk(2)
      local session = engine.create_session(old, new)
      -- from < 1 should be treated as 1
      assert.are.equal(1, session.next_undecided(0))
      assert.are.equal(1, session.next_undecided(-5))
      -- from > #hunks should still find undecided via wrap
      assert.are.equal(1, session.next_undecided(999))
    end)

    it("next_undecided(0) is clamped: finds first undecided from start", function()
      local old, new = make_multi_hunk(3)
      local session = engine.create_session(old, new)
      -- All undecided; from=0 clamps to 1, should return 1
      assert.are.equal(1, session.next_undecided(0))
    end)

    it("next_undecided with from > total wraps and scans all", function()
      local old, new = make_multi_hunk(3)
      local session = engine.create_session(old, new)
      session.accept_at(1)
      session.accept_at(2)
      -- from=999 clamped past end, wrap-around finds 3
      assert.are.equal(3, session.next_undecided(999))
    end)

    it("next_undecided returns nil on empty hunk list", function()
      local session = engine.create_session({}, {})
      assert.are.equal(0, session.get_total_hunks())
      assert.is_nil(session.next_undecided())
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

  describe("clear_at", function()
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

    it("clears an accepted decision", function()
      local old, new = make_multi_hunk(3)
      local session = engine.create_session(old, new)
      session.accept_at(2)
      assert.are.equal("accept", session.get_decision(2).decision)
      assert.is_true(session.clear_at(2))
      assert.is_nil(session.get_decision(2))
    end)

    it("clears a rejected decision", function()
      local old, new = make_multi_hunk(3)
      local session = engine.create_session(old, new)
      session.reject_at(1, "bad")
      assert.is_true(session.clear_at(1))
      assert.is_nil(session.get_decision(1))
    end)

    it("no-op on already undecided hunk", function()
      local old, new = make_multi_hunk(2)
      local session = engine.create_session(old, new)
      assert.is_true(session.clear_at(1))
      assert.is_nil(session.get_decision(1))
    end)

    it("returns false for out-of-range", function()
      local old, new = make_multi_hunk(2)
      local session = engine.create_session(old, new)
      assert.is_false(session.clear_at(0))
      assert.is_false(session.clear_at(3))
    end)

    it("clear_at followed by is_complete returns false", function()
      local old, new = make_multi_hunk(2)
      local session = engine.create_session(old, new)
      session.accept_at(1)
      session.accept_at(2)
      assert.is_true(session.is_complete())
      session.clear_at(1)
      assert.is_false(session.is_complete())
    end)

    it("finalize after clear_at treats cleared hunks as rejected with Undecided", function()
      local old, new = make_multi_hunk(2)
      local session = engine.create_session(old, new)
      session.accept_at(1)
      session.accept_at(2)
      session.clear_at(2)
      local envelope = session.finalize()
      assert.are.equal("partial", envelope.decision)
      assert.are.equal("reject", envelope.hunks[2].decision)
      assert.are.equal("Undecided", envelope.hunks[2].reason)
    end)
  end)

  describe("get_tally", function()
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

    it("all undecided", function()
      local old, new = make_multi_hunk(3)
      local session = engine.create_session(old, new)
      local tally = session.get_tally()
      assert.are.same({ accepted = 0, rejected = 0, undecided = 3 }, tally)
    end)

    it("mixed decisions", function()
      local old, new = make_multi_hunk(4)
      local session = engine.create_session(old, new)
      session.accept_at(1)
      session.accept_at(3)
      session.reject_at(2, "no")
      local tally = session.get_tally()
      assert.are.same({ accepted = 2, rejected = 1, undecided = 1 }, tally)
    end)

    it("all decided", function()
      local old, new = make_multi_hunk(2)
      local session = engine.create_session(old, new)
      session.accept_at(1)
      session.reject_at(2)
      local tally = session.get_tally()
      assert.are.same({ accepted = 1, rejected = 1, undecided = 0 }, tally)
    end)

    it("updates after clear_at", function()
      local old, new = make_multi_hunk(2)
      local session = engine.create_session(old, new)
      session.accept_at(1)
      session.accept_at(2)
      assert.are.same({ accepted = 2, rejected = 0, undecided = 0 }, session.get_tally())
      session.clear_at(1)
      assert.are.same({ accepted = 1, rejected = 0, undecided = 1 }, session.get_tally())
    end)
  end)

  describe("state machine edge cases", function()
    it("finalize is idempotent: second call returns same envelope object", function()
      local old = { "A" }
      local new = { "B" }
      local session = engine.create_session(old, new)
      session.accept()
      local e1 = session.finalize()
      local e2 = session.finalize()
      assert.are.equal(e1, e2)
    end)

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

    it("finalize() is idempotent: second call returns identical envelope", function()
      -- Use two separate hunks separated by an unchanged line
      local old = { "line 1", "old 2", "line 3", "old 4" }
      local new = { "line 1", "new 2", "line 3", "new 4" }
      local session = engine.create_session(old, new)
      assert.are.equal(2, session.get_total_hunks())
      session.accept_at(1)
      session.reject_at(2, "no")
      local e1 = session.finalize()
      local e2 = session.finalize()
      -- Must be the exact same table reference (cached)
      assert.are.equal(e1, e2)
      assert.are.equal("partial", e1.decision)
    end)

    it("finalize() with zero hunks is idempotent", function()
      local lines = { "same" }
      local session = engine.create_session(lines, lines)
      local e1 = session.finalize()
      local e2 = session.finalize()
      assert.are.equal(e1, e2)
      assert.are.equal("accept", e1.decision)
    end)
  end)
end)

describe("neph.api.review.engine boundary tests", function()
  describe("empty file boundaries", function()
    it("pure insertion at BOF: compute_hunks({}, new_lines) yields 1 hunk", function()
      local hunks = engine.compute_hunks({}, { "line1", "line2" })
      assert.are.equal(1, #hunks)
      -- start_b/end_b cover all inserted lines
      assert.are.equal(1, hunks[1].start_b)
      assert.are.equal(2, hunks[1].end_b)
    end)

    it("accepting a BOF insertion produces the new lines", function()
      local new = { "line1", "line2" }
      local session = engine.create_session({}, new)
      assert.are.equal(1, session.get_total_hunks())
      session.accept()
      local envelope = session.finalize()
      assert.are.equal("accept", envelope.decision)
      assert.are.equal("line1\nline2", envelope.content)
    end)

    it("rejecting a BOF insertion keeps old (empty) content", function()
      local session = engine.create_session({}, { "line1" })
      session.reject("no")
      local envelope = session.finalize()
      assert.are.equal("reject", envelope.decision)
      assert.are.equal("", envelope.content)
    end)

    it("pure deletion: compute_hunks(old_lines, {}) yields 1 hunk", function()
      local hunks = engine.compute_hunks({ "line1", "line2" }, {})
      assert.are.equal(1, #hunks)
    end)

    it("accepting a full deletion produces empty content", function()
      local old = { "line1", "line2" }
      local session = engine.create_session(old, {})
      assert.are.equal(1, session.get_total_hunks())
      session.accept()
      local envelope = session.finalize()
      assert.are.equal("accept", envelope.decision)
      assert.are.equal("", envelope.content)
    end)

    it("rejecting a full deletion: decision=reject, content='' (all-reject contract)", function()
      -- When all hunks are rejected, build_envelope sets content="" to signal
      -- "no accepted changes"; the caller is responsible for falling back to old.
      local old = { "line1", "line2" }
      local session = engine.create_session(old, {})
      session.reject("keep it")
      local envelope = session.finalize()
      assert.are.equal("reject", envelope.decision)
      assert.are.equal("", envelope.content)
    end)

    it("both empty: compute_hunks({}, {}) yields 0 hunks", function()
      local hunks = engine.compute_hunks({}, {})
      assert.are.equal(0, #hunks)
    end)

    it("insertion into empty file: hunk range fields are valid (no zero or negative)", function()
      local hunks = engine.compute_hunks({}, { "line1", "line2" })
      assert.are.equal(1, #hunks)
      local h = hunks[1]
      -- start_a clamped to 1 (not 0) for pure insertion into empty file
      assert.is_true(h.start_a >= 1)
      assert.is_true(h.end_a >= h.start_a)
      assert.is_true(h.start_b >= 1)
      assert.is_true(h.end_b >= h.start_b)
    end)

    it("deletion to empty file: hunk range fields are valid (no zero or negative)", function()
      local hunks = engine.compute_hunks({ "line1", "line2" }, {})
      assert.are.equal(1, #hunks)
      local h = hunks[1]
      assert.is_true(h.start_a >= 1)
      assert.is_true(h.end_a >= h.start_a)
      -- start_b clamped to 1 (not 0) for pure deletion resulting in empty
      assert.is_true(h.start_b >= 1)
      assert.is_true(h.end_b >= h.start_b)
    end)

    it("apply_decisions with all-empty inputs returns empty string without crash", function()
      local result = engine.apply_decisions({}, {}, {})
      assert.are.equal("", result)
    end)

    it("accept pure insertion (empty old → lines added) produces new content", function()
      local old = {}
      local new = { "a", "b" }
      local hunks = engine.compute_hunks(old, new)
      assert.are.equal(1, #hunks)
      local decisions = { { index = 1, decision = "accept" } }
      local result = engine.apply_decisions(old, new, decisions)
      assert.are.equal("a\nb", result)
    end)

    it("reject pure insertion (empty old → lines added) keeps empty result", function()
      local old = {}
      local new = { "a", "b" }
      local decisions = { { index = 1, decision = "reject" } }
      local result = engine.apply_decisions(old, new, decisions)
      assert.are.equal("", result)
    end)

    it("accept pure deletion (all lines removed) produces empty result", function()
      local old = { "x", "y" }
      local new = {}
      local hunks = engine.compute_hunks(old, new)
      assert.are.equal(1, #hunks)
      local decisions = { { index = 1, decision = "accept" } }
      local result = engine.apply_decisions(old, new, decisions)
      assert.are.equal("", result)
    end)

    it("reject pure deletion (all lines removed) preserves original content", function()
      local old = { "x", "y" }
      local new = {}
      local decisions = { { index = 1, decision = "reject" } }
      local result = engine.apply_decisions(old, new, decisions)
      assert.are.equal("x\ny", result)
    end)

    it("create_session with empty old lines does not crash", function()
      local session = engine.create_session({}, { "line1" })
      assert.is_not_nil(session)
      assert.are.equal(1, session.get_total_hunks())
    end)

    it("accept() on session with 0 hunks returns false", function()
      local session = engine.create_session({}, {})
      assert.are.equal(0, session.get_total_hunks())
      assert.is_true(session.is_done())
      assert.is_false(session.accept())
    end)
  end)

  describe("whitespace-only diffs", function()
    it("trailing space added is detected as a hunk", function()
      local hunks = engine.compute_hunks({ "a" }, { "a " })
      assert.are.equal(1, #hunks)
    end)

    it("leading space removed is detected as a hunk", function()
      local hunks = engine.compute_hunks({ "  a" }, { "a" })
      assert.are.equal(1, #hunks)
    end)

    it("tab removal is detected as a hunk", function()
      local hunks = engine.compute_hunks({ "a\t" }, { "a" })
      assert.are.equal(1, #hunks)
    end)
  end)

  describe("single line files", function()
    it("single line change yields 1 hunk", function()
      local hunks = engine.compute_hunks({ "x" }, { "y" })
      assert.are.equal(1, #hunks)
    end)

    it("identical single line yields 0 hunks", function()
      local hunks = engine.compute_hunks({ "x" }, { "x" })
      assert.are.equal(0, #hunks)
    end)

    it("apply_decisions single accept produces the new line", function()
      local result = engine.apply_decisions({ "x" }, { "y" }, { { index = 1, decision = "accept" } })
      assert.are.equal("y", result)
    end)

    it("apply_decisions single reject keeps the old line", function()
      local result = engine.apply_decisions({ "x" }, { "y" }, { { index = 1, decision = "reject" } })
      assert.are.equal("x", result)
    end)
  end)

  describe("index bounds", function()
    it("create_session with 1000-line file does not crash", function()
      local old = {}
      local new = {}
      for i = 1, 1000 do
        old[i] = "line_" .. i
        new[i] = "line_" .. i
      end
      -- Mutate one line to have at least 1 hunk
      new[500] = "changed_500"
      local session = engine.create_session(old, new)
      assert.is_not_nil(session)
      assert.are.equal(1, session.get_total_hunks())
    end)

    it("accept_at beyond hunk count returns false without crash", function()
      local old = { "a", "sep", "b", "sep", "c", "sep", "d", "sep", "e" }
      local new = { "A", "sep", "B", "sep", "C", "sep", "D", "sep", "E" }
      local session = engine.create_session(old, new)
      assert.are.equal(5, session.get_total_hunks())
      assert.is_false(session.accept_at(999))
    end)

    it("reject_at index 0 returns false without crash", function()
      local session = engine.create_session({ "A" }, { "B" })
      assert.is_false(session.reject_at(0))
    end)

    it("accept_at negative index returns false without crash", function()
      local session = engine.create_session({ "A" }, { "B" })
      assert.is_false(session.accept_at(-1))
    end)
  end)

  describe("build_envelope JSON-serializability", function()
    -- ReviewEnvelope must only contain primitive types (string, number, boolean, nil)
    -- and arrays/maps of those — no functions, no metatables, no circular refs.
    local function assert_json_safe(value, path)
      path = path or "envelope"
      local t = type(value)
      if t == "nil" or t == "string" or t == "number" or t == "boolean" then
        return
      end
      assert.are.equal("table", t, path .. " must be table/primitive, got " .. t)
      for k, v in pairs(value) do
        assert_json_safe(v, path .. "." .. tostring(k))
      end
    end

    it("all-accept envelope is JSON-safe", function()
      local decisions = { { index = 1, decision = "accept" } }
      local env = engine.build_envelope(decisions, "content")
      assert_json_safe(env)
    end)

    it("all-reject envelope is JSON-safe", function()
      local decisions = { { index = 1, decision = "reject", reason = "bad" } }
      local env = engine.build_envelope(decisions, "content")
      assert_json_safe(env)
    end)

    it("partial envelope is JSON-safe", function()
      local decisions = {
        { index = 1, decision = "accept" },
        { index = 2, decision = "reject", reason = "nope" },
      }
      local env = engine.build_envelope(decisions, "partial")
      assert_json_safe(env)
    end)

    it("empty decisions envelope is JSON-safe", function()
      local env = engine.build_envelope({}, "")
      assert_json_safe(env)
    end)

    it("schema field is always the literal string 'review/v1'", function()
      local env = engine.build_envelope({}, "x")
      assert.are.equal("review/v1", env.schema)
    end)
  end)

  describe("build_envelope boundaries", function()
    it("all hunks accepted → envelope.decision = 'accept'", function()
      local decisions = {
        { index = 1, decision = "accept" },
        { index = 2, decision = "accept" },
        { index = 3, decision = "accept" },
      }
      local envelope = engine.build_envelope(decisions, "content")
      assert.are.equal("accept", envelope.decision)
    end)

    it("all hunks rejected → envelope.decision = 'reject'", function()
      local decisions = {
        { index = 1, decision = "reject" },
        { index = 2, decision = "reject" },
      }
      local envelope = engine.build_envelope(decisions, "content")
      assert.are.equal("reject", envelope.decision)
    end)

    it("mixed decisions → envelope.decision = 'partial'", function()
      local decisions = {
        { index = 1, decision = "accept" },
        { index = 2, decision = "reject" },
      }
      local envelope = engine.build_envelope(decisions, "content")
      assert.are.equal("partial", envelope.decision)
    end)

    it("zero decisions → envelope.decision = 'accept'", function()
      local envelope = engine.build_envelope({}, "some content")
      assert.are.equal("accept", envelope.decision)
      assert.are.equal("some content", envelope.content)
      assert.are.equal("review/v1", envelope.schema)
    end)

    it("envelope content is always a string (JSON-serializable)", function()
      -- Accept case
      local e1 = engine.build_envelope({ { index = 1, decision = "accept" } }, "text")
      assert.are.equal("string", type(e1.content))
      -- Reject case forces content to ""
      local e2 = engine.build_envelope({ { index = 1, decision = "reject" } }, "text")
      assert.are.equal("string", type(e2.content))
      assert.are.equal("", e2.content)
      -- schema must be the literal string "review/v1"
      assert.are.equal("string", type(e1.schema))
      assert.are.equal("review/v1", e1.schema)
    end)
  end)
end)
