local engine = require("neph.api.review.engine")

describe("neph.api.review.engine", function()
  describe("compute_hunks", function()
    it("returns empty for identical lines", function()
      local lines = {"line 1", "line 2"}
      local hunks = engine.compute_hunks(lines, lines)
      assert.are.same({}, hunks)
    end)

    it("detects a replacement", function()
      local old = {"line 1", "old 2", "line 3"}
      local new = {"line 1", "new 2", "line 3"}
      local hunks = engine.compute_hunks(old, new)
      assert.are.same({{start_line = 2, end_line = 2}}, hunks)
    end)

    it("handles addition", function()
      local old = {"line 1"}
      local new = {"line 1", "line 2"}
      local hunks = engine.compute_hunks(old, new)
      assert.are.same({{start_line = 1, end_line = 1}}, hunks)
    end)
  end)

  describe("apply_decisions", function()
    it("applies accepted hunks", function()
      local old = {"line 1", "old 2", "line 3"}
      local new = {"line 1", "new 2", "line 3"}
      local decisions = {{index = 1, decision = "accept"}}
      local result = engine.apply_decisions(old, new, decisions)
      assert.are.same("line 1\nnew 2\nline 3", result)
    end)

    it("ignores rejected hunks", function()
      local old = {"line 1", "old 2", "line 3"}
      local new = {"line 1", "new 2", "line 3"}
      local decisions = {{index = 1, decision = "reject"}}
      local result = engine.apply_decisions(old, new, decisions)
      assert.are.same("line 1\nold 2\nline 3", result)
    end)

    it("applies multiple changes correctly with offset", function()
      local old = {"A", "B", "C"}
      local new = {"A", "B1", "B2", "C"}
      local hunks = engine.compute_hunks(old, new)
      assert.are.equal(1, #hunks)
      
      local decisions = {{index = 1, decision = "accept"}}
      local result = engine.apply_decisions(old, new, decisions)
      assert.are.same("A\nB1\nB2\nC", result)
    end)
  end)

  describe("state machine", function()
    it("manages a review session", function()
      local old = {"line 1", "old 2", "line 3", "old 4"}
      local new = {"line 1", "new 2", "line 3", "new 4"}
      local session = engine.create_session(old, new)
      
      assert.are.equal(2, session.get_total_hunks())
      assert.is_false(session.is_done())
      
      local hunk, idx = session.get_current_hunk()
      assert.are.equal(1, idx)
      
      session.accept()
      assert.is_false(session.is_done())
      
      hunk, idx = session.get_current_hunk()
      assert.are.equal(2, idx)
      
      session.reject("not good")
      assert.is_true(session.is_done())
      
      local envelope = session.finalize()
      assert.are.equal("partial", envelope.decision)
      assert.are.equal("line 1\nnew 2\nline 3\nold 4", envelope.content)
      assert.are.equal("not good", envelope.reason)
    end)

    it("accept_all works", function()
      local old = {"A", "B"}
      local new = {"A1", "B1"}
      local session = engine.create_session(old, new)
      session.accept_all()
      assert.is_true(session.is_done())
      local envelope = session.finalize()
      assert.are.equal("accept", envelope.decision)
      assert.are.equal("A1\nB1", envelope.content)
    end)

    it("reject_all works", function()
      local old = {"A", "B"}
      local new = {"A1", "B1"}
      local session = engine.create_session(old, new)
      session.reject_all("reason")
      assert.is_true(session.is_done())
      local envelope = session.finalize()
      assert.are.equal("reject", envelope.decision)
      assert.are.equal("", envelope.content)
      assert.are.equal("reason", envelope.reason)
    end)
  end)
end)
