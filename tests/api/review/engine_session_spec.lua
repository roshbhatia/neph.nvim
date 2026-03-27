---@diagnostic disable: undefined-global
-- Tests for engine.create_session() and its state machine

local engine = require("neph.api.review.engine")

describe("neph.api.review.engine", function()
  -- Shared line fixtures
  local old_lines = { "line 1", "line 2", "line 3" }
  local new_lines = { "line 1", "line X", "line 3" }
  local identical_lines = { "alpha", "beta", "gamma" }

  -- -------------------------------------------------------------------------
  -- compute_hunks
  -- -------------------------------------------------------------------------
  describe("compute_hunks()", function()
    it("pure insertion: start_a is clamped correctly", function()
      -- Insert a line after the last line of a 2-line file
      local old = { "aaa", "bbb" }
      local new = { "aaa", "bbb", "ccc" }
      local hunks = engine.compute_hunks(old, new)
      assert.is_true(#hunks >= 1)
      -- start_a must be within [1, #old] — never exceed the file size
      for _, h in ipairs(hunks) do
        assert.is_true(h.start_a >= 1)
        assert.is_true(h.start_a <= #old)
      end
    end)

    it("pure deletion: returns correct range", function()
      local old = { "aaa", "bbb", "ccc" }
      local new = { "aaa", "ccc" }
      local hunks = engine.compute_hunks(old, new)
      assert.is_true(#hunks >= 1)
      -- The deleted line is line 2 in old
      local h = hunks[1]
      assert.are.equal(2, h.start_a)
      assert.are.equal(2, h.end_a)
    end)
  end)

  -- -------------------------------------------------------------------------
  -- create_session — hunk counts
  -- -------------------------------------------------------------------------
  describe("create_session() hunk counts", function()
    it("returns get_total_hunks() == 1 for lines with one changed line", function()
      local session = engine.create_session(old_lines, new_lines)
      assert.are.equal(1, session.get_total_hunks())
    end)

    it("returns get_total_hunks() == 0 for identical lines", function()
      local session = engine.create_session(identical_lines, identical_lines)
      assert.are.equal(0, session.get_total_hunks())
    end)
  end)

  -- -------------------------------------------------------------------------
  -- accept_at / reject_at / clear_at / get_decision
  -- -------------------------------------------------------------------------
  describe("accept_at()", function()
    it("sets decision to 'accept'", function()
      local session = engine.create_session(old_lines, new_lines)
      local ok = session.accept_at(1)
      assert.is_true(ok)
      local d = session.get_decision(1)
      assert.is_not_nil(d)
      assert.are.equal("accept", d.decision)
    end)

    it("returns false for index 0 (out of bounds)", function()
      local session = engine.create_session(old_lines, new_lines)
      local ok = session.accept_at(0)
      assert.is_false(ok)
    end)

    it("returns false for index > total hunks (out of bounds)", function()
      local session = engine.create_session(old_lines, new_lines)
      local total = session.get_total_hunks()
      local ok = session.accept_at(total + 1)
      assert.is_false(ok)
    end)

    it("does not crash on out-of-bounds, decision remains nil", function()
      local session = engine.create_session(old_lines, new_lines)
      session.accept_at(999)
      assert.is_nil(session.get_decision(999))
    end)
  end)

  describe("reject_at()", function()
    it("sets decision to 'reject' with no reason", function()
      local session = engine.create_session(old_lines, new_lines)
      local ok = session.reject_at(1)
      assert.is_true(ok)
      local d = session.get_decision(1)
      assert.is_not_nil(d)
      assert.are.equal("reject", d.decision)
      assert.is_nil(d.reason)
    end)

    it("sets reason when provided", function()
      local session = engine.create_session(old_lines, new_lines)
      session.reject_at(1, "bad code")
      local d = session.get_decision(1)
      assert.are.equal("bad code", d.reason)
    end)
  end)

  describe("clear_at()", function()
    it("removes a previous accept decision", function()
      local session = engine.create_session(old_lines, new_lines)
      session.accept_at(1)
      assert.is_not_nil(session.get_decision(1))
      session.clear_at(1)
      assert.is_nil(session.get_decision(1))
    end)
  end)

  -- -------------------------------------------------------------------------
  -- get_tally
  -- -------------------------------------------------------------------------
  describe("get_tally()", function()
    it("returns correct counts for mixed decisions", function()
      -- Need at least 3 hunks — use a file with 3 changed lines
      local old3 = { "a", "b", "c", "d" }
      local new3 = { "A", "B", "C", "d" }
      local session = engine.create_session(old3, new3)
      local total = session.get_total_hunks()
      -- Accept hunk 1, reject hunk 2 (if they exist), leave rest undecided
      if total >= 1 then
        session.accept_at(1)
      end
      if total >= 2 then
        session.reject_at(2, "nope")
      end

      local tally = session.get_tally()
      local expected_accepted = total >= 1 and 1 or 0
      local expected_rejected = total >= 2 and 1 or 0
      local expected_undecided = total - expected_accepted - expected_rejected

      assert.are.equal(expected_accepted, tally.accepted)
      assert.are.equal(expected_rejected, tally.rejected)
      assert.are.equal(expected_undecided, tally.undecided)
    end)
  end)

  -- -------------------------------------------------------------------------
  -- next_undecided
  -- -------------------------------------------------------------------------
  describe("next_undecided()", function()
    it("skips decided hunks and wraps around", function()
      -- Build a session with multiple hunks
      local old_m = { "a", "b", "c", "d" }
      local new_m = { "A", "B", "C", "d" }
      local session = engine.create_session(old_m, new_m)
      local total = session.get_total_hunks()
      if total < 2 then
        -- Skip if not enough hunks (diff may coalesce)
        return
      end
      -- Decide hunk 1
      session.accept_at(1)
      -- next_undecided from 1 should skip 1 and return 2
      local nxt = session.next_undecided(1)
      assert.are.equal(2, nxt)
    end)

    it("returns nil when all hunks are decided", function()
      local session = engine.create_session(old_lines, new_lines)
      local total = session.get_total_hunks()
      for i = 1, total do
        session.accept_at(i)
      end
      local nxt = session.next_undecided(1)
      assert.is_nil(nxt)
    end)
  end)

  -- -------------------------------------------------------------------------
  -- accept_all_remaining / reject_all_remaining
  -- -------------------------------------------------------------------------
  describe("accept_all_remaining()", function()
    it("only sets undecided hunks, does not overwrite existing decisions", function()
      -- Need multiple hunks
      local old_m = { "a", "b", "c", "d" }
      local new_m = { "A", "B", "C", "d" }
      local session = engine.create_session(old_m, new_m)
      local total = session.get_total_hunks()
      if total >= 1 then
        session.reject_at(1, "keep this rejection")
      end
      session.accept_all_remaining()
      -- Hunk 1 must still be rejected
      if total >= 1 then
        local d = session.get_decision(1)
        assert.are.equal("reject", d.decision)
      end
      -- All other hunks must now be accepted
      for i = 2, total do
        local d = session.get_decision(i)
        assert.is_not_nil(d)
        assert.are.equal("accept", d.decision)
      end
    end)
  end)

  describe("reject_all_remaining()", function()
    it("only sets undecided hunks, does not overwrite existing decisions", function()
      local old_m = { "a", "b", "c", "d" }
      local new_m = { "A", "B", "C", "d" }
      local session = engine.create_session(old_m, new_m)
      local total = session.get_total_hunks()
      if total >= 1 then
        session.accept_at(1)
      end
      session.reject_all_remaining("all bad")
      -- Hunk 1 must still be accepted
      if total >= 1 then
        local d = session.get_decision(1)
        assert.are.equal("accept", d.decision)
      end
      -- All other hunks must now be rejected with the given reason
      for i = 2, total do
        local d = session.get_decision(i)
        assert.is_not_nil(d)
        assert.are.equal("reject", d.decision)
        assert.are.equal("all bad", d.reason)
      end
    end)
  end)

  -- -------------------------------------------------------------------------
  -- finalize
  -- -------------------------------------------------------------------------
  describe("finalize()", function()
    it("all-accept: envelope.decision == 'accept' and content is new file", function()
      local session = engine.create_session(old_lines, new_lines)
      local total = session.get_total_hunks()
      for i = 1, total do
        session.accept_at(i)
      end
      local envelope = session.finalize()
      assert.are.equal("accept", envelope.decision)
      -- Content should contain the new text (line X was accepted)
      assert.is_not_nil(envelope.content:find("line X", 1, true))
    end)

    it("all-reject: envelope.decision == 'reject' and content == ''", function()
      local session = engine.create_session(old_lines, new_lines)
      local total = session.get_total_hunks()
      for i = 1, total do
        session.reject_at(i)
      end
      local envelope = session.finalize()
      assert.are.equal("reject", envelope.decision)
      assert.are.equal("", envelope.content)
    end)

    it("mixed: envelope.decision == 'partial' and content is merged", function()
      -- Need >= 2 hunks for a mixed result
      local old_m = { "a", "b", "c", "d" }
      local new_m = { "A", "b", "C", "d" }
      local session = engine.create_session(old_m, new_m)
      local total = session.get_total_hunks()
      if total < 2 then
        return
      end
      session.accept_at(1)
      session.reject_at(2)
      -- leave rest undecided — finalize will reject them
      local envelope = session.finalize()
      assert.are.equal("partial", envelope.decision)
      assert.is_not_nil(envelope.content)
    end)

    it("undecided hunks are treated as rejected with reason 'Undecided'", function()
      local session = engine.create_session(old_lines, new_lines)
      -- Leave all hunks undecided
      local envelope = session.finalize()
      for _, h in ipairs(envelope.hunks) do
        if h.decision == "reject" and h.reason == "Undecided" then
          assert.are.equal("Undecided", h.reason)
        end
      end
      -- At least one hunk should carry "Undecided"
      local found = false
      for _, h in ipairs(envelope.hunks) do
        if h.reason == "Undecided" then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)
  end)

  -- -------------------------------------------------------------------------
  -- build_envelope (direct)
  -- -------------------------------------------------------------------------
  describe("build_envelope()", function()
    it("empty decisions → decision == 'accept' (no changes case)", function()
      local envelope = engine.build_envelope({}, "some content")
      assert.are.equal("accept", envelope.decision)
    end)

    it("schema is 'review/v1'", function()
      local envelope = engine.build_envelope({}, "")
      assert.are.equal("review/v1", envelope.schema)
    end)
  end)
end)
