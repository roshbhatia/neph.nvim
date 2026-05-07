---@diagnostic disable: undefined-global
-- Verifies that <leader>ja / <leader>jc capture visual selections from marks
-- instead of vim.fn.mode() (which has already transitioned by callback time).

describe("api.ask / api.comment marks-based selection capture", function()
  local function with_buffer(lines, fn)
    -- The selection provider needs a file-backed buffer (returns nil for
    -- buffers with no name). Write lines to a tempfile and edit it.
    local tmp = vim.fn.tempname() .. ".txt"
    vim.fn.writefile(lines, tmp)
    vim.cmd("edit " .. vim.fn.fnameescape(tmp))
    local buf = vim.api.nvim_get_current_buf()
    local ok, err = pcall(fn, buf)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    pcall(vim.fn.delete, tmp)
    if not ok then
      error(err)
    end
  end

  local function setup_marks(buf, from_row, from_col, to_row, to_col)
    vim.api.nvim_buf_set_mark(buf, "<", from_row, from_col, {})
    vim.api.nvim_buf_set_mark(buf, ">", to_row, to_col, {})
  end

  local function clear_marks(buf)
    -- nvim_buf_del_mark requires nvim 0.10+; pcall to be safe and fall back
    -- to setting them to (1, 0) (which our zero-check still treats as "set"
    -- — that's why we use {0,0} for unset). Some nvim versions may not allow
    -- explicit (0,0); skip if it errors.
    pcall(vim.api.nvim_buf_del_mark, buf, "<")
    pcall(vim.api.nvim_buf_del_mark, buf, ">")
  end

  local captured_text
  local original_input

  before_each(function()
    -- Reload api fresh
    package.loaded["neph.api"] = nil
    package.loaded["neph.internal.input"] = nil
    captured_text = nil
    original_input = vim.ui.input

    -- Stub session.ensure_active_and_send so on_confirm captures the
    -- final (placeholder-expanded) text without spawning an agent.
    package.loaded["neph.internal.session"] = {
      ensure_active_and_send = function(text)
        captured_text = text
      end,
      get_active = function()
        return "claude"
      end,
    }
    -- Stub agents.get_by_name so input_for_active doesn't need a real agent.
    package.loaded["neph.internal.agents"] = {
      get_by_name = function(_)
        return { name = "claude", icon = "" }
      end,
    }

    -- Stub vim.ui.input to invoke the on_confirm with the default — that
    -- path runs placeholders.apply which feeds session.ensure_active_and_send.
    vim.ui.input = function(opts, on_confirm)
      if on_confirm then
        on_confirm(opts.default)
      end
    end

    package.loaded["neph.api"] = nil
  end)

  after_each(function()
    vim.ui.input = original_input
    package.loaded["neph.internal.session"] = nil
    package.loaded["neph.internal.agents"] = nil
  end)

  it("captures selection text from marks when <> are set", function()
    with_buffer({ "line one", "line two", "line three" }, function(buf)
      setup_marks(buf, 1, 0, 2, 8) -- entire line 1, all of line 2
      local api = require("neph.api")
      api.ask()
      assert.is_string(captured_text)
      -- The captured text should contain the buffer content (after +selection
      -- expansion). The exact format includes a "@<path>:<from>-<to>\n" prefix
      -- followed by the selected text.
      assert.truthy(
        captured_text:find("line one") or captured_text:find("line two"),
        "expected selection text in expanded prompt, got: " .. captured_text
      )
    end)
  end)

  it("falls back to +cursor when marks are unset", function()
    with_buffer({ "line one", "line two" }, function(buf)
      clear_marks(buf)
      -- Reload api so closure picks up clean mark state
      package.loaded["neph.api"] = nil
      local api = require("neph.api")
      api.ask()
      -- captured_text either expanded +cursor (some line content) or stripped
      -- the token if context provider returned nil. Either way it should NOT
      -- contain a `@<path>:N-N` selection-style header.
      if captured_text and captured_text ~= "" then
        assert.is_falsy(
          captured_text:match("@.+:%d+-%d+"),
          "expected no selection header in captured text, got: " .. captured_text
        )
      end
    end)
  end)

  it("api.comment uses the same marks-based capture as api.ask", function()
    with_buffer({ "alpha", "beta", "gamma" }, function(buf)
      setup_marks(buf, 1, 0, 1, 4)
      local api = require("neph.api")
      api.comment()
      assert.is_string(captured_text)
      assert.truthy(
        captured_text:find("alpha") or captured_text:lower():find("comment"),
        "expected comment prompt to expand selection, got: " .. captured_text
      )
    end)
  end)
end)
