---@diagnostic disable: undefined-global
-- tests/api/diff_spec.lua
-- Unit tests for neph.api.diff (review + picker) and neph.internal.git

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function fresh_diff(mock_git, mock_session, mock_config, mock_gitsigns, mock_snacks)
  -- Inject dependency mocks before requiring the module under test.
  package.loaded["neph.internal.git"] = mock_git
  package.loaded["neph.internal.session"] = mock_session
  package.loaded["neph.config"] = mock_config
  if mock_gitsigns ~= nil then
    package.loaded["gitsigns"] = mock_gitsigns
  end
  if mock_snacks ~= nil then
    package.loaded["snacks"] = mock_snacks
  end
  package.loaded["neph.api.diff"] = nil
  return require("neph.api.diff")
end

local function cleanup()
  package.loaded["neph.internal.git"] = nil
  package.loaded["neph.internal.session"] = nil
  package.loaded["neph.config"] = nil
  package.loaded["gitsigns"] = nil
  package.loaded["snacks"] = nil
  package.loaded["neph.api.diff"] = nil
end

local function make_config(overrides)
  local cfg = vim.tbl_deep_extend("force", {
    diff = {
      prompts = {
        review = "Review this diff.",
        hunk = "Review this hunk.",
      },
      branch_fallback = "HEAD~1",
    },
  }, overrides or {})
  return { current = cfg }
end

-- ---------------------------------------------------------------------------
-- neph.api.diff — review()
-- ---------------------------------------------------------------------------

describe("neph.api.diff.review", function()
  local sent_messages = {}
  local mock_session
  local mock_git

  before_each(function()
    sent_messages = {}
    mock_session = {
      ensure_active_and_send = function(msg)
        table.insert(sent_messages, msg)
      end,
    }
    mock_git = {
      diff_lines = function(scope, _opts)
        if scope == "head" then
          return { "diff --git a/foo.lua b/foo.lua", "+added line" }, nil
        end
        return nil, "no diff"
      end,
      in_git_repo = function()
        return true
      end,
      merge_base = function()
        return "abc123", nil
      end,
    }
  end)

  after_each(function()
    cleanup()
  end)

  -- 6.2: review("head") — stub git.diff_lines, assert ensure_active_and_send called
  describe('review("head")', function()
    it("calls ensure_active_and_send with a formatted message", function()
      local diff = fresh_diff(mock_git, mock_session, make_config())
      local ok, err = diff.review("head")
      assert.is_true(ok)
      assert.is_nil(err)
      assert.are.equal(1, #sent_messages)
      local msg = sent_messages[1]
      -- Message must contain the prompt and the diff block
      assert.truthy(msg:find("Review this diff", 1, true))
      assert.truthy(msg:find("```diff", 1, true))
      assert.truthy(msg:find("+added line", 1, true))
    end)

    it("returns false and does not send when diff is empty", function()
      mock_git.diff_lines = function()
        return nil, nil
      end
      local diff = fresh_diff(mock_git, mock_session, make_config())
      local ok, err = diff.review("head")
      assert.is_false(ok)
      assert.is_string(err)
      assert.are.equal(0, #sent_messages)
    end)
  end)

  -- 6.3: review("hunk") — stub gitsigns hunks
  describe('review("hunk")', function()
    it("sends hunk lines to agent", function()
      local mock_gs = {
        get_hunks = function()
          return {
            {
              head = "@@ -1,3 +1,4 @@",
              added = { start = 1, count = 4 },
              lines = { "+new line", " context", "-removed" },
            },
          }
        end,
      }
      local diff = fresh_diff(mock_git, mock_session, make_config(), mock_gs)
      -- Position cursor on line 1 (inside the hunk)
      vim.fn.setpos(".", { 0, 1, 1, 0 })
      local ok, err = diff.review("hunk")
      assert.is_true(ok)
      assert.is_nil(err)
      assert.are.equal(1, #sent_messages)
      local msg = sent_messages[1]
      assert.truthy(msg:find("Review this hunk", 1, true))
      assert.truthy(msg:find("@@ -1,3 +1,4 @@", 1, true))
    end)

    it("returns error when gitsigns is unavailable", function()
      -- Ensure gitsigns cannot be required
      package.loaded["gitsigns"] = nil
      local diff = fresh_diff(mock_git, mock_session, make_config(), false)
      -- Override pcall result: gitsigns not on package.loaded → require fails
      -- Because fresh_diff passes false, pcall(require, "gitsigns") will fail
      -- (false is not a valid module). Revert to nil so the require actually fails.
      package.loaded["gitsigns"] = nil
      local ok, err = diff.review("hunk")
      assert.is_false(ok)
      assert.is_string(err)
      assert.are.equal(0, #sent_messages)
    end)

    it("returns error when buffer has no hunks", function()
      local mock_gs = {
        get_hunks = function()
          return {}
        end,
      }
      local diff = fresh_diff(mock_git, mock_session, make_config(), mock_gs)
      local ok, err = diff.review("hunk")
      assert.is_false(ok)
      assert.is_string(err)
      assert.are.equal(0, #sent_messages)
    end)
  end)

  -- 6.4: empty diff — assert notify called, ensure_active_and_send not called
  describe("empty diff", function()
    it("notifies and does not send when diff lines are empty", function()
      mock_git.diff_lines = function()
        return {}, nil
      end
      local notified = false
      local orig_notify = vim.notify
      vim.notify = function(_msg, _level)
        notified = true
      end
      local diff = fresh_diff(mock_git, mock_session, make_config())
      local ok, _err = diff.review("head")
      vim.notify = orig_notify
      assert.is_false(ok)
      assert.is_true(notified)
      assert.are.equal(0, #sent_messages)
    end)

    it("notifies and does not send when diff_lines returns nil+nil", function()
      mock_git.diff_lines = function()
        return nil, nil
      end
      local notified = false
      local orig_notify = vim.notify
      vim.notify = function(_msg, _level)
        notified = true
      end
      local diff = fresh_diff(mock_git, mock_session, make_config())
      local ok, _err = diff.review("head")
      vim.notify = orig_notify
      assert.is_false(ok)
      assert.is_true(notified)
      assert.are.equal(0, #sent_messages)
    end)
  end)

  -- 6.5: no active agent — session notifies; no crash in diff module
  describe("no active agent", function()
    it("does not crash when session.ensure_active_and_send is called with no agent", function()
      -- The session module is responsible for notifying when no agent is active.
      -- diff.review should still call ensure_active_and_send and return true.
      local session_called = false
      mock_session.ensure_active_and_send = function(_msg)
        session_called = true
        -- Simulate what session does: notify but don't error
        vim.notify("No active AI terminal", vim.log.levels.WARN)
      end
      local diff = fresh_diff(mock_git, mock_session, make_config())
      local ok, err = diff.review("head")
      assert.is_true(ok)
      assert.is_nil(err)
      assert.is_true(session_called)
    end)
  end)
end)

-- ---------------------------------------------------------------------------
-- neph.api.diff — picker()
-- ---------------------------------------------------------------------------

describe("neph.api.diff.picker", function()
  local mock_git
  local picker_calls = {}

  before_each(function()
    picker_calls = {}
    mock_git = {
      merge_base = function(_opts)
        return "abc123", nil
      end,
      in_git_repo = function()
        return true
      end,
    }
  end)

  after_each(function()
    cleanup()
  end)

  local function make_snacks(capture)
    return {
      picker = {
        git_diff = function(opts)
          table.insert(capture, opts or {})
        end,
      },
    }
  end

  it('picker("head") calls snacks.picker.git_diff with no args', function()
    local diff = fresh_diff(mock_git, {}, make_config(), nil, make_snacks(picker_calls))
    local ok, err = diff.picker("head")
    assert.is_true(ok)
    assert.is_nil(err)
    assert.are.equal(1, #picker_calls)
  end)

  it('picker("staged") calls snacks.picker.git_diff with staged=true', function()
    local diff = fresh_diff(mock_git, {}, make_config(), nil, make_snacks(picker_calls))
    local ok, err = diff.picker("staged")
    assert.is_true(ok)
    assert.is_nil(err)
    assert.are.equal(1, #picker_calls)
    assert.is_true(picker_calls[1].staged)
  end)

  it('picker("branch") resolves merge-base and passes base to git_diff', function()
    local diff = fresh_diff(mock_git, {}, make_config(), nil, make_snacks(picker_calls))
    local ok, err = diff.picker("branch")
    assert.is_true(ok)
    assert.is_nil(err)
    assert.are.equal(1, #picker_calls)
    assert.are.equal("abc123", picker_calls[1].base)
  end)

  it('picker("branch") uses branch_fallback when merge-base fails', function()
    mock_git.merge_base = function()
      return nil, "no remote"
    end
    local diff = fresh_diff(mock_git, {}, make_config(), nil, make_snacks(picker_calls))
    local ok, err = diff.picker("branch")
    assert.is_true(ok)
    assert.is_nil(err)
    assert.are.equal(1, #picker_calls)
    assert.are.equal("HEAD~1", picker_calls[1].base)
  end)

  it("returns error when snacks is unavailable", function()
    package.loaded["snacks"] = nil
    local diff = fresh_diff(mock_git, {}, make_config(), nil, false)
    package.loaded["snacks"] = nil
    local ok, err = diff.picker("head")
    assert.is_false(ok)
    assert.is_string(err)
  end)

  it("returns error for invalid scope", function()
    local diff = fresh_diff(mock_git, {}, make_config(), nil, make_snacks(picker_calls))
    local ok, err = diff.picker("hunk")
    assert.is_false(ok)
    assert.is_string(err)
    assert.are.equal(0, #picker_calls)
  end)
end)

-- ---------------------------------------------------------------------------
-- neph.internal.git — diff_lines for non-git directory
-- ---------------------------------------------------------------------------

describe("neph.internal.git", function()
  local function fresh_git()
    package.loaded["neph.internal.git"] = nil
    return require("neph.internal.git")
  end

  after_each(function()
    package.loaded["neph.internal.git"] = nil
  end)

  -- 6.6: diff_lines returns nil + error for non-git dir
  describe("diff_lines", function()
    it("returns nil and an error string for a non-git directory", function()
      local g = fresh_git()
      -- /tmp is reliably not a git repository
      local lines, err = g.diff_lines("head", { cwd = "/tmp" })
      assert.is_nil(lines)
      assert.is_string(err)
      assert.truthy(err:find("git", 1, true) or err:find("repository", 1, true) or err:find("Not", 1, true))
    end)

    it("returns nil and an error for unsupported scope", function()
      local g = fresh_git()
      -- Use cwd that is likely in a git repo (the plugin itself)
      local lines, err = g.diff_lines("bogus", { cwd = vim.fn.getcwd() })
      assert.is_nil(lines)
      assert.is_string(err)
    end)

    it("returns nil and error when file scope has no file arg", function()
      local g = fresh_git()
      local lines, err = g.diff_lines("file", { cwd = vim.fn.getcwd() })
      assert.is_nil(lines)
      assert.is_string(err)
    end)
  end)

  describe("in_git_repo", function()
    it("returns false for /tmp", function()
      local g = fresh_git()
      assert.is_false(g.in_git_repo("/tmp"))
    end)

    it("returns true for the plugin directory", function()
      local g = fresh_git()
      -- The test suite runs from inside the neph.nvim git repo
      assert.is_true(g.in_git_repo(vim.fn.getcwd()))
    end)
  end)
end)
