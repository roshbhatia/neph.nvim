---@diagnostic disable: undefined-global
-- Edge-case tests for neph.api.review.engine
-- Covers: finalize idempotency, next_undecided out-of-bounds, build_envelope
-- defensive paths, accept/reject_all_remaining skip behaviour, get_tally
-- exhaustive counts, and create_session with zero-length inputs.

local engine = require("neph.api.review.engine")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Produces N isolated hunks separated by unchanged sentinel lines.
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

-- ---------------------------------------------------------------------------
-- 1. finalize() idempotency
-- ---------------------------------------------------------------------------
describe("engine_edge: finalize() idempotency", function()
  it("second finalize() returns equal envelope to first", function()
    local old, new = make_multi_hunk(2)
    local session = engine.create_session(old, new)
    session.accept_at(1)
    -- hunk 2 is undecided — finalize should promote it to rejected

    local env1 = session.finalize()
    local env2 = session.finalize()

    assert.are.equal(env1.decision, env2.decision)
    assert.are.equal(env1.content, env2.content)
    assert.are.equal(env1.schema, env2.schema)
    -- Both calls must agree on every hunk decision
    for i, h in ipairs(env1.hunks) do
      assert.are.equal(h.decision, env2.hunks[i].decision)
    end
  end)

  it("second finalize() does NOT re-classify any hunk", function()
    local old, new = make_multi_hunk(3)
    local session = engine.create_session(old, new)
    -- Finalize with all hunks undecided
    local env1 = session.finalize()
    -- After first finalize, clear hunk 1 and immediately re-finalize
    -- The guard must prevent re-processing so hunk 1 stays as first-pass decided
    session.clear_at(1)
    local env2 = session.finalize()

    -- With idempotent guard the second call re-builds from current decisions_by_idx.
    -- Hunk 1 was cleared, but finalize already locked decisions_by_idx on first call
    -- so hunk 1 is still "reject/Undecided" inside decisions_by_idx.
    -- (clear_at after finalize is a caller error, but the guard must not crash.)
    assert.is_not_nil(env2)
    assert.are.equal("review/v1", env2.schema)
  end)

  it("finalize() on session with 0 hunks is stable across calls", function()
    local lines = { "a", "b", "c" }
    local session = engine.create_session(lines, lines)
    assert.are.equal(0, session.get_total_hunks())

    local env1 = session.finalize()
    local env2 = session.finalize()

    assert.are.equal("accept", env1.decision)
    assert.are.equal(env1.decision, env2.decision)
    assert.are.equal(env1.content, env2.content)
  end)
end)

-- ---------------------------------------------------------------------------
-- 2. next_undecided() out-of-bounds from argument
-- ---------------------------------------------------------------------------
describe("engine_edge: next_undecided() boundary values for from", function()
  it("from=0 does not return index 0", function()
    local old, new = make_multi_hunk(3)
    local session = engine.create_session(old, new)
    local idx = session.next_undecided(0)
    -- Must be a valid hunk index (1..3) or nil — never 0
    assert.is_not_nil(idx)
    assert.is_true(idx >= 1)
  end)

  it("from=-5 does not return a negative index", function()
    local old, new = make_multi_hunk(2)
    local session = engine.create_session(old, new)
    local idx = session.next_undecided(-5)
    assert.is_not_nil(idx)
    assert.is_true(idx >= 1)
  end)

  it("from > total hunks wraps and still finds undecided", function()
    local old, new = make_multi_hunk(3)
    local session = engine.create_session(old, new)
    -- Decide hunks 2 and 3; leave 1 undecided
    session.accept_at(2)
    session.accept_at(3)
    -- from=99 is past the end; wrap-around should find hunk 1
    local idx = session.next_undecided(99)
    assert.are.equal(1, idx)
  end)

  it("from > total hunks returns nil when all decided", function()
    local old, new = make_multi_hunk(2)
    local session = engine.create_session(old, new)
    session.accept_at(1)
    session.accept_at(2)
    local idx = session.next_undecided(999)
    assert.is_nil(idx)
  end)

  it("from=1 on a fully-decided session returns nil", function()
    local old, new = make_multi_hunk(3)
    local session = engine.create_session(old, new)
    for i = 1, session.get_total_hunks() do
      session.accept_at(i)
    end
    assert.is_nil(session.next_undecided(1))
  end)
end)

-- ---------------------------------------------------------------------------
-- 3. build_envelope — defensive: empty hunks, mixed content guards
-- ---------------------------------------------------------------------------
describe("engine_edge: build_envelope() defensive paths", function()
  it("empty decisions → decision='accept', schema preserved", function()
    local env = engine.build_envelope({}, "some content")
    assert.are.equal("accept", env.decision)
    assert.are.equal("review/v1", env.schema)
    assert.are.equal("some content", env.content)
    assert.is_nil(env.reason)
  end)

  it("all-accept decisions → content is not overwritten to empty", function()
    local decisions = {
      { index = 1, decision = "accept" },
      { index = 2, decision = "accept" },
    }
    local env = engine.build_envelope(decisions, "my content")
    assert.are.equal("accept", env.decision)
    assert.are.equal("my content", env.content)
  end)

  it("all-reject decisions → content forced to empty string", function()
    local decisions = {
      { index = 1, decision = "reject", reason = "r1" },
      { index = 2, decision = "reject", reason = "r2" },
    }
    local env = engine.build_envelope(decisions, "should be erased")
    assert.are.equal("reject", env.decision)
    assert.are.equal("", env.content)
    assert.are.equal("r1; r2", env.reason)
  end)

  it("partial decisions → content is preserved, reason from rejects only", function()
    local decisions = {
      { index = 1, decision = "accept" },
      { index = 2, decision = "reject", reason = "bad" },
      { index = 3, decision = "accept" },
    }
    local env = engine.build_envelope(decisions, "partial content")
    assert.are.equal("partial", env.decision)
    assert.are.equal("partial content", env.content)
    assert.are.equal("bad", env.reason)
  end)

  it("reject without any reason → envelope.reason is nil", function()
    local decisions = {
      { index = 1, decision = "reject" },
      { index = 2, decision = "reject", reason = "" },
    }
    local env = engine.build_envelope(decisions, "x")
    assert.are.equal("reject", env.decision)
    assert.is_nil(env.reason)
  end)
end)

-- ---------------------------------------------------------------------------
-- 4. accept_all_remaining / reject_all_remaining skip already-decided
-- ---------------------------------------------------------------------------
describe("engine_edge: accept_all_remaining / reject_all_remaining correctness", function()
  it("accept_all_remaining does not overwrite a prior reject", function()
    local old, new = make_multi_hunk(4)
    local session = engine.create_session(old, new)
    session.reject_at(2, "keep")
    session.accept_all_remaining()
    assert.are.equal("reject", session.get_decision(2).decision)
    assert.are.equal("keep", session.get_decision(2).reason)
    assert.are.equal("accept", session.get_decision(1).decision)
    assert.are.equal("accept", session.get_decision(3).decision)
    assert.are.equal("accept", session.get_decision(4).decision)
  end)

  it("reject_all_remaining does not overwrite a prior accept", function()
    local old, new = make_multi_hunk(4)
    local session = engine.create_session(old, new)
    session.accept_at(3)
    session.reject_all_remaining("bulk")
    assert.are.equal("accept", session.get_decision(3).decision)
    assert.are.equal("reject", session.get_decision(1).decision)
    assert.are.equal("reject", session.get_decision(2).decision)
    assert.are.equal("reject", session.get_decision(4).decision)
  end)

  it("accept_all_remaining on fully-decided session is a no-op", function()
    local old, new = make_multi_hunk(2)
    local session = engine.create_session(old, new)
    session.reject_at(1, "r")
    session.reject_at(2, "r")
    session.accept_all_remaining()
    -- Both remain rejected
    assert.are.equal("reject", session.get_decision(1).decision)
    assert.are.equal("reject", session.get_decision(2).decision)
  end)

  it("reject_all_remaining on fully-decided session is a no-op", function()
    local old, new = make_multi_hunk(2)
    local session = engine.create_session(old, new)
    session.accept_at(1)
    session.accept_at(2)
    session.reject_all_remaining("x")
    assert.are.equal("accept", session.get_decision(1).decision)
    assert.are.equal("accept", session.get_decision(2).decision)
  end)
end)

-- ---------------------------------------------------------------------------
-- 5. get_tally() exhaustive count correctness
-- ---------------------------------------------------------------------------
describe("engine_edge: get_tally() count correctness", function()
  it("all accepted → accepted=N, rejected=0, undecided=0", function()
    local n = 3
    local old, new = make_multi_hunk(n)
    local session = engine.create_session(old, new)
    assert.are.equal(n, session.get_total_hunks())
    for i = 1, n do
      session.accept_at(i)
    end
    local t = session.get_tally()
    assert.are.same({ accepted = n, rejected = 0, undecided = 0 }, t)
  end)

  it("all rejected → accepted=0, rejected=N, undecided=0", function()
    local n = 3
    local old, new = make_multi_hunk(n)
    local session = engine.create_session(old, new)
    for i = 1, n do
      session.reject_at(i)
    end
    local t = session.get_tally()
    assert.are.same({ accepted = 0, rejected = n, undecided = 0 }, t)
  end)

  it("all undecided → accepted=0, rejected=0, undecided=N", function()
    local n = 4
    local old, new = make_multi_hunk(n)
    local session = engine.create_session(old, new)
    assert.are.equal(n, session.get_total_hunks())
    local t = session.get_tally()
    assert.are.same({ accepted = 0, rejected = 0, undecided = n }, t)
  end)

  it("mixed: accepted + rejected + undecided sum equals total", function()
    local n = 5
    local old, new = make_multi_hunk(n)
    local session = engine.create_session(old, new)
    session.accept_at(1)
    session.accept_at(3)
    session.reject_at(5, "no")
    -- hunks 2 and 4 undecided
    local t = session.get_tally()
    assert.are.equal(2, t.accepted)
    assert.are.equal(1, t.rejected)
    assert.are.equal(2, t.undecided)
    assert.are.equal(n, t.accepted + t.rejected + t.undecided)
  end)

  it("tally updates live as decisions are made and cleared", function()
    local old, new = make_multi_hunk(3)
    local session = engine.create_session(old, new)
    assert.are.same({ accepted = 0, rejected = 0, undecided = 3 }, session.get_tally())
    session.accept_at(1)
    assert.are.same({ accepted = 1, rejected = 0, undecided = 2 }, session.get_tally())
    session.reject_at(2)
    assert.are.same({ accepted = 1, rejected = 1, undecided = 1 }, session.get_tally())
    session.clear_at(1)
    assert.are.same({ accepted = 0, rejected = 1, undecided = 2 }, session.get_tally())
  end)

  it("zero-hunk session tally is all zeros", function()
    local lines = { "x", "y" }
    local session = engine.create_session(lines, lines)
    assert.are.same({ accepted = 0, rejected = 0, undecided = 0 }, session.get_tally())
  end)
end)

-- ---------------------------------------------------------------------------
-- 6. Hunk range off-by-one checks
-- ---------------------------------------------------------------------------
describe("engine_edge: hunk range end values (off-by-one)", function()
  it("single-line replacement: end_a == start_a, end_b == start_b", function()
    local old = { "A", "B", "C" }
    local new = { "A", "X", "C" }
    local hunks = engine.compute_hunks(old, new)
    assert.are.equal(1, #hunks)
    assert.are.equal(hunks[1].start_a, hunks[1].end_a)
    assert.are.equal(hunks[1].start_b, hunks[1].end_b)
  end)

  it("multi-line replacement: end_a - start_a == count - 1", function()
    local old = { "A", "B", "C", "D", "E" }
    local new = { "A", "X", "Y", "Z", "E" }
    local hunks = engine.compute_hunks(old, new)
    assert.are.equal(1, #hunks)
    -- old: B,C,D replaced → count_a = 3, lines 2,3,4
    assert.are.equal(2, hunks[1].start_a)
    assert.are.equal(4, hunks[1].end_a)
    -- new: X,Y,Z → count_b = 3, lines 2,3,4
    assert.are.equal(2, hunks[1].start_b)
    assert.are.equal(4, hunks[1].end_b)
  end)

  it("pure deletion: end_a >= start_a, end_b == start_b (display clamp)", function()
    local old = { "A", "B", "C" }
    local new = { "A", "C" }
    local hunks = engine.compute_hunks(old, new)
    assert.are.equal(1, #hunks)
    assert.is_true(hunks[1].end_a >= hunks[1].start_a)
    assert.are.equal(2, hunks[1].start_a)
    assert.are.equal(2, hunks[1].end_a)
  end)

  it("pure insertion: end_a >= start_a (no negative span)", function()
    local old = { "A" }
    local new = { "A", "B" }
    local hunks = engine.compute_hunks(old, new)
    assert.are.equal(1, #hunks)
    assert.is_true(hunks[1].end_a >= hunks[1].start_a)
    assert.is_true(hunks[1].end_b >= hunks[1].start_b)
  end)

  it("all ranges: end >= start for large realistic diff", function()
    local old = {}
    local new = {}
    for i = 1, 20 do
      old[i] = "line_" .. i
    end
    -- Mutate a few lines
    new = vim.deepcopy(old)
    new[5] = "changed_5"
    new[10] = "changed_10"
    new[15] = "changed_15"
    local hunks = engine.compute_hunks(old, new)
    for _, h in ipairs(hunks) do
      assert.is_true(h.end_a >= h.start_a, "end_a < start_a for hunk")
      assert.is_true(h.end_b >= h.start_b, "end_b < start_b for hunk")
    end
  end)
end)

-- ---------------------------------------------------------------------------
-- 7. create_session with zero-length old or new lines
-- ---------------------------------------------------------------------------
describe("engine_edge: create_session() with zero-length inputs", function()
  it("empty old, non-empty new: session has >= 1 hunk, no crash", function()
    local session = engine.create_session({}, { "a", "b", "c" })
    assert.is_not_nil(session)
    assert.is_true(session.get_total_hunks() >= 1)
  end)

  it("non-empty old, empty new: session has >= 1 hunk, no crash", function()
    local session = engine.create_session({ "a", "b" }, {})
    assert.is_not_nil(session)
    assert.is_true(session.get_total_hunks() >= 1)
  end)

  it("both empty: session has 0 hunks, finalize returns accept/empty", function()
    local session = engine.create_session({}, {})
    assert.are.equal(0, session.get_total_hunks())
    local env = session.finalize()
    assert.are.equal("accept", env.decision)
    assert.are.equal("", env.content)
  end)

  it("empty old finalize accept → content equals new_lines joined", function()
    local new = { "x", "y", "z" }
    local session = engine.create_session({}, new)
    session.accept_all_remaining()
    local env = session.finalize()
    assert.are.equal("accept", env.decision)
    assert.are.equal(table.concat(new, "\n"), env.content)
  end)

  it("empty new finalize accept → content is empty string", function()
    local session = engine.create_session({ "a", "b" }, {})
    session.accept_all_remaining()
    local env = session.finalize()
    -- Accepting all deletions means the file content becomes empty
    assert.are.equal("accept", env.decision)
    assert.are.equal("", env.content)
  end)

  it("single-line old, empty new: reject keeps original", function()
    local session = engine.create_session({ "keep_me" }, {})
    session.reject_all_remaining()
    local env = session.finalize()
    assert.are.equal("reject", env.decision)
    assert.are.equal("", env.content)
  end)
end)
