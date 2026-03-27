-- Tests for neph.api.review.queue_ui
-- Covers: renders active + queued entries, dd cancels, empty queue message, <CR> opens file

local h = require("tests.test_helpers")

describe("queue_ui", function()
  local rq
  local queue_ui

  before_each(function()
    rq = require("neph.internal.review_queue")
    rq._reset()
    -- set a no-op open_fn so enqueue works
    rq.set_open_fn(function() end)
    queue_ui = require("neph.api.review.queue_ui")
  end)

  after_each(function()
    rq._reset()
    -- close any open windows
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local ok, buf = pcall(vim.api.nvim_win_get_buf, win)
      if ok then
        local ft = vim.bo[buf].filetype
        if ft == "neph-queue" then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    end
    package.loaded["neph.api.review.queue_ui"] = nil
  end)

  local function find_queue_win()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "neph-queue" then
        return win, buf
      end
    end
    return nil, nil
  end

  local function get_lines(buf)
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end

  it("shows empty message when no reviews pending", function()
    queue_ui.open()
    local win, buf = find_queue_win()
    assert.is_not_nil(win)
    local lines = get_lines(buf)
    local text = table.concat(lines, "\n")
    assert.truthy(text:find("no pending reviews"))
  end)

  it("shows active review", function()
    rq.enqueue({
      request_id = "r1",
      path = "/tmp/active.lua",
      result_path = "/tmp/r1",
      channel_id = 0,
      content = "",
      agent = "amp",
    })
    queue_ui.open()
    local win, buf = find_queue_win()
    assert.is_not_nil(win)
    local lines = get_lines(buf)
    local text = table.concat(lines, "\n")
    assert.truthy(text:find("active%.lua"))
    assert.truthy(text:find("%[amp%]"))
  end)

  it("shows queued entries numbered", function()
    rq.enqueue({
      request_id = "r1",
      path = "/tmp/first.lua",
      result_path = "/tmp/r1",
      channel_id = 0,
      content = "",
      agent = "amp",
    })
    rq.enqueue({
      request_id = "r2",
      path = "/tmp/second.lua",
      result_path = "/tmp/r2",
      channel_id = 0,
      content = "",
      agent = "amp",
    })
    rq.enqueue({
      request_id = "r3",
      path = "/tmp/third.lua",
      result_path = "/tmp/r3",
      channel_id = 0,
      content = "",
      agent = "amp",
    })
    queue_ui.open()
    local _, buf = find_queue_win()
    assert.is_not_nil(buf)
    local lines = get_lines(buf)
    local text = table.concat(lines, "\n")
    assert.truthy(text:find("second%.lua"))
    assert.truthy(text:find("third%.lua"))
    -- Should be numbered starting at 1
    assert.truthy(text:find("1%."))
    assert.truthy(text:find("2%."))
  end)

  it("q closes the window", function()
    queue_ui.open()
    local win, buf = find_queue_win()
    assert.is_not_nil(win)
    -- invoke q keymap directly
    local keymaps = vim.api.nvim_buf_get_keymap(buf, "n")
    local q_map
    for _, km in ipairs(keymaps) do
      if km.lhs == "q" then
        q_map = km
        break
      end
    end
    assert.is_not_nil(q_map)
    q_map.callback()
    assert.falsy(vim.api.nvim_win_is_valid(win))
  end)

  it("dd on queued entry cancels that path", function()
    rq.enqueue({ request_id = "r1", path = "/tmp/active.lua", result_path = "/tmp/r1", channel_id = 0, content = "" })
    rq.enqueue({ request_id = "r2", path = "/tmp/queued.lua", result_path = "/tmp/r2", channel_id = 0, content = "" })

    queue_ui.open()
    local win, buf = find_queue_win()
    assert.is_not_nil(win)

    -- find the queued entry line
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local queued_row
    for i, line in ipairs(lines) do
      if line:find("queued%.lua") then
        queued_row = i
        break
      end
    end
    assert.is_not_nil(queued_row)

    -- move cursor to that row
    vim.api.nvim_win_set_cursor(win, { queued_row, 0 })

    -- invoke dd keymap
    local keymaps = vim.api.nvim_buf_get_keymap(buf, "n")
    local dd_map
    for _, km in ipairs(keymaps) do
      if km.lhs == "dd" then
        dd_map = km
        break
      end
    end
    assert.is_not_nil(dd_map)
    dd_map.callback()

    -- queued.lua should be gone from the queue
    local q = rq.get_queue()
    local found = false
    for _, req in ipairs(q) do
      if req.path == "/tmp/queued.lua" then
        found = true
      end
    end
    assert.falsy(found)
  end)

  it("r keymap refreshes buffer content", function()
    rq.enqueue({ request_id = "r1", path = "/tmp/active.lua", result_path = "/tmp/r1", channel_id = 0, content = "" })

    queue_ui.open()
    local _, buf = find_queue_win()
    assert.is_not_nil(buf)

    -- enqueue another while window is open
    rq.enqueue({ request_id = "r2", path = "/tmp/newfile.lua", result_path = "/tmp/r2", channel_id = 0, content = "" })

    -- invoke r keymap
    local keymaps = vim.api.nvim_buf_get_keymap(buf, "n")
    local r_map
    for _, km in ipairs(keymaps) do
      if km.lhs == "r" then
        r_map = km
        break
      end
    end
    assert.is_not_nil(r_map)
    r_map.callback()

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(lines, "\n")
    assert.truthy(text:find("newfile%.lua"))
  end)
end)
